import os
from clickhouse_driver import Client

# --- Configuration ---
# Get ClickHouse host from environment variable, default to our Docker setup
CLICKHOUSE_HOST = os.environ.get("CLICKHOUSE_HOST", "localhost")
CLICKHOUSE_PORT = int(os.environ.get("CLICKHOUSE_PORT", 8123))

# We will query the 'default' database
CLICKHOUSE_DB = "default"

# --- Client Function ---

def get_clickhouse_client():
    """
    Creates and returns a ClickHouse client connection.
    Manages connection settings in one place.
    """
    try:
        client = Client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB
            # user='default', # default user
            # password='',   # default password
        )
        
        # Verify the connection works
        if not client.is_readonly():
            print(f"Successfully connected to ClickHouse at {CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}")
        else:
            print(f"Warning: Connected to ClickHouse in read-only mode.")
            
        return client
        
    except Exception as e:
        print(f"CRITICAL: Could not connect to ClickHouse at {CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}")
        print(f"Error: {e}")
        # In a real app, you might exit or retry, but here we'll let the error propagate
        raise

# --- Example Usage (for testing this file directly) ---
if __name__ == "__main__":
    try:
        # Create a client
        client = get_clickhouse_client()
        
        # Run a simple test query
        print("\nRunning a test query: 'SHOW TABLES'")
        tables = client.execute('SHOW TABLES')
        
        print("Test query successful. Found tables:")
        for (table,) in tables:
            print(f"- {table}")
            
    except Exception as e:
        print(f"Test query failed: {e}")