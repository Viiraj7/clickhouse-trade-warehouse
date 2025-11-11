import json
import random
import time
from datetime import datetime
from kafka import KafkaProducer

BROKER = "localhost:29092"
TOPIC = "ticks"

symbols = ["AAPL", "GOOG", "MSFT", "TSLA"]
sides = ["BUY", "SELL"]
exchanges = ["NASDAQ", "NYSE"]

def generate_tick(trade_id):
    return {
        "trade_id": trade_id,
        "symbol": random.choice(symbols),
        "event_time": datetime.utcnow().isoformat(timespec="milliseconds") + "Z",
        "price": round(random.uniform(100, 300), 2),
        "volume": random.randint(1, 500),
        "side": random.choice(sides),
        "exchange": random.choice(exchanges)
    }

def main():
    print(f"Connecting to Kafka broker at {BROKER}...")

    producer = KafkaProducer(
        bootstrap_servers=[BROKER],
        value_serializer=lambda x: json.dumps(x).encode("utf-8")
    )

    print("✅ Connected! Sending real tick events...")

    trade_id = 0
    while True:
        tick = generate_tick(trade_id)
        producer.send(TOPIC, tick)

        if trade_id % 100 == 0:
            print(f"Sent {trade_id} ticks...")

        trade_id += 1
        time.sleep(0.005)  # ~200 ticks per second

if __name__ == "__main__":
    main()
