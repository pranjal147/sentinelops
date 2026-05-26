"""
Remediation agent — consumes anomalies, calls Claude with tool-use,
checks OPA policy, executes kubectl actions.
"""
import os
import json
import asyncio
import logging
from datetime import datetime, timezone

import httpx
import anthropic
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
from kubernetes import client as k8s_client, config as k8s_config

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("remediation-agent")

KAFKA_BROKERS   = os.getenv("KAFKA_BROKERS", "redpanda-0.redpanda.platform.svc.cluster.local:9093")
INPUT_TOPIC     = os.getenv("INPUT_TOPIC", "anomalies")
OUTPUT_TOPIC    = os.getenv("OUTPUT_TOPIC", "remediation-log")
OPA_URL         = os.getenv("OPA_URL", "http://localhost:8181/v1/data/remediation/allow")
ANTHROPIC_KEY   = os.getenv("ANTHROPIC_API_KEY", "")
CLAUDE_MODEL    = os.getenv("CLAUDE_MODEL", "claude-3-5-haiku-20241022")

# Tool definitions for Claude
TOOLS = [
    {
        "name": "get_pod_status",
        "description": "Get status of pods in a Kubernetes namespace",
        "input_schema": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string", "description": "Kubernetes namespace"},
            },
            "required": ["namespace"],
        },
    },
    {
        "name": "restart_pod",
        "description": "Restart a Kubernetes deployment by rolling restart",
        "input_schema": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string"},
                "deployment": {"type": "string"},
            },
            "required": ["namespace", "deployment"],
        },
    },
    {
        "name": "scale_deployment",
        "description": "Scale a Kubernetes deployment to a given number of replicas",
        "input_schema": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string"},
                "deployment": {"type": "string"},
                "replicas": {"type": "integer", "minimum": 1, "maximum": 5},
            },
            "required": ["namespace", "deployment", "replicas"],
        },
    },
]


def load_k8s():
    try:
        k8s_config.load_incluster_config()
    except Exception:
        k8s_config.load_kube_config()


def get_pod_status(namespace: str) -> str:
    v1 = k8s_client.CoreV1Api()
    pods = v1.list_namespaced_pod(namespace)
    lines = []
    for pod in pods.items:
        phase = pod.status.phase or "Unknown"
        restarts = sum(
            cs.restart_count for cs in (pod.status.container_statuses or [])
        )
        lines.append(f"{pod.metadata.name}: {phase}, restarts={restarts}")
    return "\n".join(lines) if lines else "No pods found"


def restart_pod(namespace: str, deployment: str) -> str:
    apps_v1 = k8s_client.AppsV1Api()
    now = datetime.now(timezone.utc).isoformat()
    patch = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {"kubectl.kubernetes.io/restartedAt": now}
                }
            }
        }
    }
    apps_v1.patch_namespaced_deployment(deployment, namespace, patch)
    return f"Restarted deployment/{deployment} in {namespace}"


def scale_deployment(namespace: str, deployment: str, replicas: int) -> str:
    apps_v1 = k8s_client.AppsV1Api()
    patch = {"spec": {"replicas": replicas}}
    apps_v1.patch_namespaced_deployment_scale(deployment, namespace, patch)
    return f"Scaled deployment/{deployment} in {namespace} to {replicas} replicas"


async def check_opa(action: str, **kwargs) -> bool:
    payload = {"input": {"action": action, **kwargs}}
    async with httpx.AsyncClient(timeout=5.0) as c:
        try:
            r = await c.post(OPA_URL, json=payload)
            return r.json().get("result", False)
        except Exception as e:
            log.error("OPA check failed: %s", e)
            return False


def execute_tool(tool_name: str, tool_input: dict) -> str:
    if tool_name == "get_pod_status":
        return get_pod_status(tool_input["namespace"])
    elif tool_name == "restart_pod":
        return restart_pod(tool_input["namespace"], tool_input["deployment"])
    elif tool_name == "scale_deployment":
        return scale_deployment(
            tool_input["namespace"], tool_input["deployment"], tool_input["replicas"]
        )
    return "Unknown tool"


async def handle_anomaly(anomaly: dict, producer: AIOKafkaProducer):
    log.info("Handling anomaly: %s", anomaly)

    claude = anthropic.Anthropic(api_key=ANTHROPIC_KEY)
    system = (
        "You are a Kubernetes SRE agent. Analyze the anomaly and use tools to "
        "investigate and remediate. Be conservative — only restart if clearly needed. "
        "Always check pod status before taking action."
    )
    user_msg = f"Anomaly detected:\n{json.dumps(anomaly, indent=2)}\n\nInvestigate and remediate if needed."

    messages = [{"role": "user", "content": user_msg}]
    actions_taken = []

    for _ in range(5):  # max 5 tool calls
        try:
            response = claude.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=1024,
                system=system,
                tools=TOOLS,
                messages=messages,
            )
        except Exception as e:
            log.error("Claude API error: %s", e)
            return

        if response.stop_reason == "end_turn":
            conclusion = next(
                (b.text for b in response.content if hasattr(b, "text")), "Done"
            )
            log.info("Claude conclusion: %s", conclusion)
            break

        tool_results = []
        for block in response.content:
            if block.type != "tool_use":
                continue

            tool_name = block.name
            tool_input = block.input

            # OPA policy check before any mutating action
            opa_input = {**tool_input, "action": tool_name, "severity": anomaly.get("severity", "warning")}
            allowed = await check_opa(**opa_input) if tool_name != "get_pod_status" else True

            if not allowed:
                result = f"DENIED by OPA policy: action={tool_name} input={tool_input}"
                log.warning(result)
            else:
                result = execute_tool(tool_name, tool_input)
                log.info("EXECUTED %s(%s) → %s", tool_name, tool_input, result)
                actions_taken.append({"tool": tool_name, "input": tool_input, "result": result})

            tool_results.append({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": result,
            })

        messages.append({"role": "assistant", "content": response.content})
        messages.append({"role": "user", "content": tool_results})

    log_entry = {
        "anomaly": anomaly,
        "actions_taken": actions_taken,
        "timestamp": anomaly.get("timestamp"),
    }
    await producer.send(OUTPUT_TOPIC, log_entry)


async def run():
    load_k8s()
    consumer = AIOKafkaConsumer(
        INPUT_TOPIC,
        bootstrap_servers=KAFKA_BROKERS,
        group_id="remediation-agent",
        value_deserializer=lambda v: json.loads(v.decode()),
        auto_offset_reset="latest",
    )
    producer = AIOKafkaProducer(
        bootstrap_servers=KAFKA_BROKERS,
        value_serializer=lambda v: json.dumps(v).encode(),
    )
    await consumer.start()
    await producer.start()
    log.info("Remediation agent started. Consuming '%s'", INPUT_TOPIC)

    try:
        async for msg in consumer:
            await handle_anomaly(msg.value, producer)
    finally:
        await consumer.stop()
        await producer.stop()


if __name__ == "__main__":
    asyncio.run(run())
