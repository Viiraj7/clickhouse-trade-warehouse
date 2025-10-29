import time
import json
import random
from kafka import KafkaProducer
from datetime import datetime
import os

# --- Configuration ---
# We get the Kafka Broker address from an environment variable,
# defaulting to our docker-compose port exposed externally.
KAFKA_TOPIC = "ticks"
KAFKA_BROKER = os.environ.get("KAFKA_BROKER", "localhost:29092") # Use 29092 for external access

# List of symbols to simulate
SYMBOLS = [
    "AAPL", "GOOG", "MSFT", "AMZN", "TSLA",
    "BTC-USD", "ETH-USD", "EUR-USD", "USD-JPY"
]

# --- Helper Functions ---

def get_iso_timestamp():
    """Returns a high-precision ISO 8601 timestamp string for ClickHouse DateTime64(6)."""
    # ClickHouse format: YYYY-MM-DD HH:MM:SS.ffffff
    return datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S.%f')

def create_mock_trade(seq_id):
    """Generates a single mock trade event."""
    symbol = random.choice(SYMBOLS)

    # Base price depends on symbol
    if "USD" in symbol and symbol != "BTC-USD" and symbol != "ETH-USD":
        base_price = 1.1 if symbol == "EUR-USD" else 150.0 # Forex or JPY
    elif "BTC" in symbol:
        base_price = 60000
    elif "ETH" in symbol:
        base_price = 4000
    elif symbol == "AAPL":
        base_price = 170
    elif symbol == "GOOG":
        base_price = 2800
    elif symbol == "MSFT":
        base_price = 300
    elif symbol == "AMZN":
        base_price = 3300
    elif symbol == "TSLA":
        base_price = 700
    else:
        base_price = 200 # Default for safety

    # Simulate price fluctuation
    price = round(base_price + random.uniform(-base_price * 0.001, base_price * 0.001), 6) # Tiny % fluctuation
    size = random.randint(1, 100)

    # Simulate ~5% duplicates/corrections for ReplacingMergeTree demo
    version = seq_id # Normally, version increases monotonically
    current_seq_id = seq_id # The actual event ID

    if random.random() < 0.05:
        # Simulate a late arrival or correction: use an older seq_id
        # but keep the version increasing.
        current_seq_id = max(0, seq_id - random.randint(100, 200))
        # For ReplacingMergeTree, the version *must* be higher for the correction
        # Let's just use the current seq_id as the version for simplicity
        version = seq_id

    trade = {
        "exchange": "XNAS", # Simulate NASDAQ
        "symbol": symbol,
        "event_time": get_iso_timestamp(), # ClickHouse DateTime64 format
        "seq_id": current_seq_id,          # ID of the event (can be old)
        "event_type": "trade",             # Only sending trades for now
        "price": price,
        "size": size,
        "side": random.choice(["buy", "sell"]),
        "source_version": version          # Increasing version for ReplacingMergeTree
    }
    return trade

def serialize_json(data):
    """Custom JSON serializer for Kafka."""
    # Ensure correct encoding for Kafka bytes
    return json.dumps(data).encode('utf-8')

# --- Main Producer Logic ---

def main():
    print(f"Attempting to connect to Kafka broker at {KAFKA_BROKER}...")
    producer = None
    # Retry connection for robustness
    for _ in range(5): # Retry 5 times
        try:
            producer = KafkaProducer(
                bootstrap_servers=[KAFKA_BROKER],
                value_serializer=serialize_json,
                acks='1',  # Wait for leader ack only
                retries=3  # Retry sending messages if transient error occurs
            )
            print("Successfully connected to Kafka!")
            break # Exit loop if connection successful
        except Exception as e:
            print(f"Connection attempt failed: {e}. Retrying in 5 seconds...")
            time.sleep(5)

    if producer is None:
        print("ERROR: Could not connect to Kafka after multiple attempts. Exiting.")
        return

    seq_id_counter = 0
    try:
        print(f"Starting to send data to Kafka topic '{KAFKA_TOPIC}'...")
        while True:
            # Generate a trade event
            trade_data = create_mock_trade(seq_id_counter)

            # Use the stock symbol as the Kafka message key
            # This ensures messages for the same symbol go to the same partition,
            # maintaining order for that symbol.
            key = trade_data['symbol'].encode('utf-8')

            # Send the message to the Kafka topic
            producer.send(KAFKA_TOPIC, value=trade_data, key=key)

            # Log progress periodically
            if seq_id_counter % 100 == 0:
                # Flush messages every 100 sends to reduce latency visibility
                producer.flush(timeout=1) # Wait max 1 sec for ack
                print(f"Sent 100 messages. Current version: {seq_id_counter}")
                if seq_id_counter % 1000 == 0:
                     print(f"Sample data: {trade_data}") # Print a sample every 1000 messages

            seq_id_counter += 1

            # Control the rate of message production
            # 0.01 seconds = approx 100 messages/second
            # Adjust this value to simulate higher/lower throughput
            time.sleep(0.01)

    except KeyboardInterrupt:
        print("\nCtrl+C detected. Stopping producer gracefully...")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    finally:
        if producer:
            print("Flushing final messages...")
            producer.flush() # Ensure all buffered messages are sent
            print("Closing Kafka producer connection.")
            producer.close()
            print("Producer closed.")

if __name__ == "__main__":
    main()