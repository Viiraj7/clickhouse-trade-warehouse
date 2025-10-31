import uvicorn
from fastapi import FastAPI, HTTPException
from clickhouse_client import get_clickhouse_client
import time

# Create the FastAPI app instance
app = FastAPI(
    title="ClickHouse Trade Analytics API",
    description="API for querying the real-time trade warehouse and backtest engine."
)

# --- Database Connection ---

# We instantiate one client when the app starts.
# For a production app, you might use a more complex connection pool.
try:
    client = get_clickhouse_client()
except Exception as e:
    print(f"FATAL: Could not connect to ClickHouse on startup. {e}")
    # In a real app, you might not want to exit, but for this demo,
    # if the DB isn't up, the API is useless.
    client = None 

# --- API Endpoints ---

@app.get("/")
def read_root():
    """Root endpoint to check if the API is running."""
    return {"status": "ClickHouse Analytics API is running."}

# ---
# 1. THE BENCHMARK ENDPOINTS (FAST VS. SLOW)
# ---

@app.get("/backtest/slow")
def run_backtest_slow(symbol: str = "AAPL", limit: int = 100):
    """
    Runs the "SLOW" backtest query.
    This query calculates 1-minute OHLCV/VWAP by scanning
    the raw 'ticks_all' table.
    """
    if client is None:
        raise HTTPException(status_code=503, detail="Database connection not available.")

    # This is the "slow" query. It must scan raw data and group it.
    query = f"""
    SELECT
        toStartOfMinute(event_time) AS minute,
        symbol,
        argMin(price, event_time) AS open,
        max(price) AS high,
        min(price) AS low,
        argMax(price, event_time) AS close,
        sum(size) AS volume,
        sum(price * size) / sum(size) AS vwap
    FROM 
        default.ticks_all -- Query the Distributed table
    WHERE 
        symbol = %(symbol)s 
        AND event_type = 'trade'
    GROUP BY 
        symbol, minute
    ORDER BY 
        minute DESC
    LIMIT %(limit)s
    """
    
    try:
        start_time = time.perf_counter()
        result = client.execute(query, {'symbol': symbol, 'limit': limit}, with_column_types=True)
        end_time = time.perf_counter()
        
        # Process results into a nice JSON
        columns = [col[0] for col in result[1]]
        data = [dict(zip(columns, row)) for row in result[0]]
        
        return {
            "query_type": "slow",
            "query_time_ms": (end_time - start_time) * 1000,
            "rows_returned": len(data),
            "data": data
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/backtest/fast")
def run_backtest_fast(symbol: str = "AAPL", limit: int = 100):
    """
    Runs the "FAST" backtest query.
    This query reads from the pre-aggregated 'trades_1m_agg' table.
    """
    if client is None:
        raise HTTPException(status_code=503, detail="Database connection not available.")

    # This is the "fast" query. It reads pre-calculated states.
    query = f"""
    SELECT
        minute,
        symbol,
        -- Use '...Merge' functions to finalize the aggregate states
        argMinMerge(open) AS open,
        maxMerge(high) AS high,
        minMerge(low) AS low,
        argMaxMerge(close) AS close,
        sumMerge(volume) AS volume,
        sumMerge(vwap_pv) / sumMerge(volume) AS vwap
    FROM 
        default.trades_1m_agg -- Query the AGGREGATING table
    WHERE 
        symbol = %(symbol)s
    GROUP BY 
        symbol, minute
    ORDER BY 
        minute DESC
    LIMIT %(limit)s
    """
    
    try:
        start_time = time.perf_counter()
        result = client.execute(query, {'symbol': symbol, 'limit': limit}, with_column_types=True)
        end_time = time.perf_counter()
        
        # Process results into a nice JSON
        columns = [col[0] for col in result[1]]
        data = [dict(zip(columns, row)) for row in result[0]]
        
        return {
            "query_type": "fast",
            "query_time_ms": (end_time - start_time) * 1000,
            "rows_returned": len(data),
            "data": data
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ---
# 2. THE DEDUPLICATION BENCHMARK ENDPOINTS
# ---

@app.get("/dedup/raw_count")
def get_dedup_raw_count(symbol: str = "AAPL"):
    """
    Gets the raw row count from the dedup table (FAST, but includes duplicates).
    """
    if client is None:
        raise HTTPException(status_code=503, detail="Database connection not available.")
    
    query = "SELECT count() FROM default.ticks_dedup WHERE symbol = %(symbol)s"
    
    try:
        start_time = time.perf_counter()
        (count,) = client.execute(query, {'symbol': symbol})[0]
        end_time = time.perf_counter()
        
        return {
            "query_type": "raw_count",
            "query_time_ms": (end_time - start_time) * 1000,
            "symbol": symbol,
            "count": count
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/dedup/final_count")
def get_dedup_final_count(symbol: str = "AAPL"):
    """
    Gets the deduplicated row count using the 'FINAL' keyword (SLOWER, but accurate).
    """
    if client is None:
        raise HTTPException(status_code=503, detail="Database connection not available.")
    
    # The FINAL keyword forces ClickHouse to perform the merge
    # logic on the fly, giving us the accurate, deduplicated count.
    query = "SELECT count() FROM default.ticks_dedup FINAL WHERE symbol = %(symbol)s"
    
    try:
        start_time = time.perf_counter()
        (count,) = client.execute(query, {'symbol': symbol})[0]
        end_time = time.perf_counter()
        
        return {
            "query_type": "final_count",
            "query_time_ms": (end_time - start_time) * 1000,
            "symbol": symbol,
            "count": count
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---
# 3. (STRETCH GOAL) HOT PATH ENDPOINT
# ---
# We will fill this in later if we build the realtime_cache.
@app.get("/realtime/book-depth")
def get_book_depth(symbol: str = "AAPL"):
    # This endpoint will NOT query ClickHouse.
    # It will query the in-memory Segment Tree from 'realtime_cache.py'
    return {"status": "hot-path-not-implemented", "symbol": symbol}


# ---
# Run the application
# ---
if __name__ == "__main__":
    print("Starting FastAPI server...")
    uvicorn.run(app, host="0.0.0.0", port=8000)