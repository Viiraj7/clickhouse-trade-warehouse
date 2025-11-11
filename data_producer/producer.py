import time
import json
import random
from kafka import KafkaProducer
from datetime import datetime, timezone
import os

KAFKA_TOPIC = "ticks"
KAFKA_BROKER = os.environ.get("KAFKA_BROKER", "localhost:29092")

SYMBOLS = ["AAPL", "GOOG", "MSFT", "TSLA"]

def encode_json(data):
    return json.dumps(data).encode("utf-8")

def main():
    print(f"Connecting to Kafka broker at {KAFKA_BROKER}...")

    producer = None
    for attempt in range(1, 6):
        try:
            producer = KafkaProducer(
                bootstrap_servers=[KAFKA_BROKER],
                value_serializer=encode_json
            )
            print("✅ Connected! Sending events...")
            break
        except Exception as e:
            print(f"❌ Attempt {attempt}/5 failed: {e}")
            time.sleep(2)

    if producer is None:
        print("❌ Could not connect to Kafka.")
        return

    i = 0
    while True:
        msg = {"id": i, "symbol": random.choice(SYMBOLS)}
        producer.send(KAFKA_TOPIC, value=msg)
        if i % 100 == 0:
            producer.flush()
            print(f"Sent {i} events...")
        i += 1
        time.sleep(0.01)

if __name__ == "__main__":
    main()
