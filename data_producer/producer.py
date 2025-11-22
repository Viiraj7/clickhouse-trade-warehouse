import json
import random
import time
from datetime import datetime
from kafka import KafkaProducer

BROKER = "localhost:29092"
TOPIC = "ticks"

symbols = ["AAPL", "GOOG", "MSFT", "TSLA"]
sides = ["buy", "sell"]  # Must match Enum8('buy' = 1, 'sell' = 2)
exchanges = ["NASDAQ", "NYSE"]
event_types = ["trade", "quote", "book"]  # Must match Enum8('trade' = 1, 'quote' = 2, 'book' = 3)

# Track recent seq_ids for corrections
recent_seq_ids = []

def generate_tick(seq_id):
    """
    Generates a tick event matching the ClickHouse schema:
    - exchange, symbol, event_time, seq_id, event_type, price, size, side, source_version
    
    Occasionally generates corrections (duplicate seq_id with higher source_version)
    to test the ReplacingMergeTree deduplication.
    """
    global recent_seq_ids
    
    # Simulate occasional corrections (1% chance)
    # A correction reuses a previous seq_id with a higher source_version
    is_correction = random.random() < 0.01 and len(recent_seq_ids) > 0
    
    if is_correction:
        # Reuse a recent seq_id with a higher version
        corrected_seq_id = random.choice(recent_seq_ids)
        source_version = random.randint(2, 100)  # Higher version for correction
    else:
        corrected_seq_id = seq_id
        source_version = 1
        # Keep track of recent seq_ids (last 100)
        recent_seq_ids.append(seq_id)
        if len(recent_seq_ids) > 100:
            recent_seq_ids.pop(0)
    
    return {
        "exchange": random.choice(exchanges),
        "symbol": random.choice(symbols),
        "event_time": datetime.utcnow().isoformat(timespec="microseconds") + "Z",
        "seq_id": corrected_seq_id,
        "event_type": random.choice(event_types),  # Usually 'trade', but can be 'quote' or 'book'
        "price": round(random.uniform(100, 300), 2),
        "size": random.randint(1, 500),  # Renamed from 'volume' to match schema
        "side": random.choice(sides),
        "source_version": source_version
    }

def main():
    print(f"Connecting to Kafka broker at {BROKER}...")

    producer = KafkaProducer(
        bootstrap_servers=[BROKER],
        value_serializer=lambda x: json.dumps(x).encode("utf-8")
    )

    print("✅ Connected! Sending real tick events...")
    print("Press Ctrl+C to stop.")

    seq_id = 0
    try:
        while True:
            tick = generate_tick(seq_id)
            producer.send(TOPIC, tick)

            if seq_id % 1000 == 0:
                print(f"Sent {seq_id} ticks...")

            seq_id += 1
            time.sleep(0.0005)  # ~2000 ticks per second
    except KeyboardInterrupt:
        print("\n\nStopping producer...")
        producer.flush()
        producer.close()
        print("Producer stopped.")

if __name__ == "__main__":
    main()
