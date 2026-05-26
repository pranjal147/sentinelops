"""
Anomaly detector — consumes predictions topic, detects anomalies, publishes to anomalies topic.

Detects:
  - high_latency:      latency_ms > LATENCY_THRESHOLD_MS
  - prediction_spike:  rolling avg fraud probability > PREDICTION_SPIKE_THRESHOLD
  - feature_outlier:   Isolation Forest score on input features (after warmup)
"""
import os
import json
import asyncio
import logging
import numpy as np
from collections import deque
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
from sklearn.ensemble import IsolationForest

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("anomaly-detector")

KAFKA_BROKERS        = os.getenv("KAFKA_BROKERS", "redpanda-0.redpanda.platform.svc.cluster.local:9093")
INPUT_TOPIC          = os.getenv("INPUT_TOPIC", "predictions")
OUTPUT_TOPIC         = os.getenv("OUTPUT_TOPIC", "anomalies")
LATENCY_THRESHOLD_MS = float(os.getenv("LATENCY_THRESHOLD_MS", "500"))
PREDICTION_WINDOW    = int(os.getenv("PREDICTION_WINDOW", "50"))
SPIKE_THRESHOLD      = float(os.getenv("SPIKE_THRESHOLD", "0.3"))
IFOREST_WARMUP       = int(os.getenv("IFOREST_WARMUP", "100"))

prediction_window: deque = deque(maxlen=PREDICTION_WINDOW)
feature_buffer: list = []
iforest: IsolationForest | None = None


def check_anomalies(event: dict) -> list[dict]:
    anomalies = []
    latency = event.get("latency_ms", 0)
    predictions = event.get("predictions", [0.0])
    instances = event.get("instances", [[]])
    fraud_prob = predictions[0] if predictions else 0.0

    # Rule 1: high latency
    if latency > LATENCY_THRESHOLD_MS:
        anomalies.append({
            "type": "high_latency",
            "value": latency,
            "threshold": LATENCY_THRESHOLD_MS,
            "severity": "warning",
        })

    # Rule 2: prediction spike (rolling window avg)
    prediction_window.append(fraud_prob)
    if len(prediction_window) >= 10:
        rolling_avg = float(np.mean(prediction_window))
        if rolling_avg > SPIKE_THRESHOLD:
            anomalies.append({
                "type": "prediction_spike",
                "value": rolling_avg,
                "threshold": SPIKE_THRESHOLD,
                "severity": "critical",
            })

    # Rule 3: feature outlier (Isolation Forest after warmup)
    global iforest, feature_buffer
    if instances and instances[0]:
        feature_buffer.append(instances[0])
        if len(feature_buffer) == IFOREST_WARMUP:
            iforest = IsolationForest(contamination=0.05, random_state=42)
            iforest.fit(feature_buffer)
            log.info("Isolation Forest fitted on %d samples", IFOREST_WARMUP)
        elif iforest is not None:
            score = iforest.decision_function([instances[0]])[0]
            if score < -0.1:
                anomalies.append({
                    "type": "feature_outlier",
                    "value": float(score),
                    "threshold": -0.1,
                    "severity": "warning",
                })

    return anomalies


async def run():
    consumer = AIOKafkaConsumer(
        INPUT_TOPIC,
        bootstrap_servers=KAFKA_BROKERS,
        group_id="anomaly-detector",
        value_deserializer=lambda v: json.loads(v.decode()),
        auto_offset_reset="latest",
    )
    producer = AIOKafkaProducer(
        bootstrap_servers=KAFKA_BROKERS,
        value_serializer=lambda v: json.dumps(v).encode(),
    )

    await consumer.start()
    await producer.start()
    log.info("Anomaly detector started. Consuming '%s' → publishing to '%s'", INPUT_TOPIC, OUTPUT_TOPIC)

    try:
        async for msg in consumer:
            event = msg.value
            anomalies = check_anomalies(event)
            for anomaly in anomalies:
                alert = {
                    "request_id": event.get("request_id"),
                    "timestamp": event.get("timestamp"),
                    **anomaly,
                }
                await producer.send(OUTPUT_TOPIC, alert)
                log.warning("ANOMALY request_id=%s type=%s value=%s",
                            alert["request_id"], alert["type"], alert["value"])
    finally:
        await consumer.stop()
        await producer.stop()


if __name__ == "__main__":
    asyncio.run(run())
