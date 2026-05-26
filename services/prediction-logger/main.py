import os
import time
import json
import uuid
import logging
import asyncio

import httpx
from aiokafka import AIOKafkaProducer
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("prediction-logger")

PREDICTOR_URL = os.getenv("PREDICTOR_URL", "http://fraud-lgbm-predictor.serving.svc.cluster.local/v1/models/fraud-lgbm:predict")
KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "redpanda.platform.svc.cluster.local:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "predictions")

app = FastAPI(title="prediction-logger")
producer: AIOKafkaProducer = None


class PredictRequest(BaseModel):
    instances: list


@app.on_event("startup")
async def startup():
    global producer
    producer = AIOKafkaProducer(
        bootstrap_servers=KAFKA_BROKERS,
        value_serializer=lambda v: json.dumps(v).encode(),
    )
    await producer.start()
    log.info("Kafka producer started, brokers=%s", KAFKA_BROKERS)


@app.on_event("shutdown")
async def shutdown():
    if producer:
        await producer.stop()


@app.get("/healthz")
async def health():
    return {"status": "ok"}


@app.post("/v1/models/fraud-lgbm:predict")
async def predict(req: PredictRequest):
    start = time.time()
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.post(PREDICTOR_URL, json={"instances": req.instances})
            resp.raise_for_status()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=502, detail=str(e))

    latency_ms = round((time.time() - start) * 1000, 2)
    predictions = resp.json().get("predictions", [])

    event = {
        "request_id": str(uuid.uuid4()),
        "timestamp": time.time(),
        "instances": req.instances,
        "predictions": predictions,
        "latency_ms": latency_ms,
    }

    await producer.send(KAFKA_TOPIC, event)
    log.info("request_id=%s prediction=%s latency_ms=%s", event["request_id"], predictions, latency_ms)

    return {"predictions": predictions, "request_id": event["request_id"], "latency_ms": latency_ms}
