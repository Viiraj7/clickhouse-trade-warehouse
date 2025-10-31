import streamlit as st
import requests
import pandas as pd
import plotly.graph_objects as go
import time

# --- Page Configuration ---
st.set_page_config(
    page_title="ClickHouse Trade Analytics",
    page_icon="⚡",
    layout="wide"
)

# --- API Configuration ---
API_BASE_URL = "http://localhost:8000"  # This is our FastAPI server

# --- Helper Functions ---

def fetch_api_data(endpoint: str, params: dict):
    """Helper function to call our FastAPI and return the JSON response."""
    try:
        response = requests.get(f"{API_BASE_URL}{endpoint}", params=params, timeout=60) # 60 sec timeout for slow query
        response.raise_for_status()  # Raise an error for bad responses (4xx, 5xx)
        return response.json()
    except requests.exceptions.ConnectionError:
        return {"error": "ConnectionError", "detail": "Could not connect to the API. Is it running?"}
    except requests.exceptions.RequestException as e:
        return {"error": str(e), "detail": f"API request failed: {e}"}

def create_candlestick_chart(data: list):
    """Creates a Plotly Candlestick chart from our API data."""
    if not data:
        return go.Figure()

    df = pd.DataFrame(data)
    # Ensure correct data types
    df['minute'] = pd.to_datetime(df['minute'])
    df['open'] = pd.to_numeric(df['open'])
    df['high'] = pd.to_numeric(df['high'])
    df['low'] = pd.to_numeric(df['low'])
    df['close'] = pd.to_numeric(df['close'])
    
    fig = go.Figure(data=[go.Candlestick(
        x=df['minute'],
        open=df['open'],
        high=df['high'],
        low=df['low'],
        close=df['close'],
        name="OHLC"
    )])
    
    fig.update_layout(
        title="1-Minute OHLCV",
        xaxis_title="Time",
        yaxis_title="Price",
        xaxis_rangeslider_visible=False,
        template="plotly_dark"
    )
    return fig

# --- Main Application ---
st.title("⚡ Real-Time Trade Analytics Warehouse")
st.subheader("Powered by ClickHouse, Kafka, and FastAPI")

st.info("This dashboard demonstrates the performance difference between querying raw data vs. pre-aggregated rollups in ClickHouse.")

# --- 1. Backtest Benchmark Section ---
st.header("1. Backtest Query Benchmark (Fast vs. Slow)")
st.write("Run the same 1-minute OHLCV query against two different tables:")
st.write("  - **Slow Query:** Scans the raw `ticks_all` table (millions of rows).")
st.write("  - **Fast Query:** Reads from the `trades_1m_agg` rollup table (thousands of rows).")

col1, col2 = st.columns(2)
with col1:
    symbol = st.text_input("Enter Symbol:", "AAPL", key="benchmark_symbol").upper()
with col2:
    limit = st.number_input("Number of minutes to fetch:", 10, 5000, 100, key="benchmark_limit")

# --- Run Slow Query ---
if st.button("Run SLOW Query (Raw Scan)", type="secondary"):
    st.subheader("Slow Query (Raw Scan)")
    with st.spinner(f"Running slow query for {symbol} on `ticks_all`... This may take a moment."):
        params = {"symbol": symbol, "limit": limit}
        result = fetch_api_data("/backtest/slow", params)
        
    if "error" in result:
        st.error(f"Error: {result['detail']}")
    else:
        st.metric("Query Time", f"{result['query_time_ms']:.2f} ms")
        st.metric("Rows Returned", result['rows_returned'])
        
        with st.expander("Show Candlestick Chart"):
            fig = create_candlestick_chart(result.get('data', []))
            st.plotly_chart(fig, use_container_width=True)
        with st.expander("Show Raw JSON Response"):
            st.json(result, expanded=False)

# --- Run Fast Query ---
if st.button("Run FAST Query (Rollup)", type="primary"):
    st.subheader("Fast Query (AggregatingMergeTree Rollup)")
    with st.spinner(f"Running fast query for {symbol} on `trades_1m_agg`..."):
        params = {"symbol": symbol, "limit": limit}
        result = fetch_api_data("/backtest/fast", params)
        
    if "error" in result:
        st.error(f"Error: {result['detail']}")
    else:
        st.metric("Query Time", f"{result['query_time_ms']:.2f} ms")
        st.metric("Rows Returned", result['rows_returned'])
        
        with st.expander("Show Candlestick Chart", expanded=True):
            fig = create_candlestick_chart(result.get('data', []))
            st.plotly_chart(fig, use_container_width=True)
        with st.expander("Show Raw JSON Response"):
            st.json(result, expanded=False)

st.divider()

# --- 2. Deduplication Benchmark Section ---
st.header("2. Deduplication Benchmark (`ReplacingMergeTree`)")
st.write("This tests the difference between a simple `COUNT()` vs. a `COUNT() ... FINAL` on our deduplication table.")
st.write("  - **Raw Count:** Very fast, but includes temporary duplicates.")
st.write("  - **Final Count:** Slower, but 100% accurate (forces ClickHouse to apply deduplication logic *now*).")

dedup_symbol = st.text_input("Enter Symbol:", "AAPL", key="dedup_symbol").upper()

if st.button("Run Deduplication Benchmark"):
    col_raw, col_final = st.columns(2)
    
    # --- Raw Count ---
    with col_raw:
        st.subheader("Raw Count (Fast, Unclean)")
        with st.spinner("Getting raw count..."):
            params = {"symbol": dedup_symbol}
            result_raw = fetch_api_data("/dedup/raw_count", params)
        
        if "error" in result_raw:
            st.error(f"Error: {result_raw['detail']}")
        else:
            st.metric("Query Time", f"{result_raw['query_time_ms']:.2f} ms")
            st.metric("Total Rows (with duplicates)", result_raw['count'])

    # --- Final Count ---
    with col_final:
        st.subheader("Final Count (Slower, Clean)")
        with st.spinner("Getting FINAL count... This may take a moment."):
            params = {"symbol": dedup_symbol}
            result_final = fetch_api_data("/dedup/final_count", params)
        
        if "error" in result_final:
            st.error(f"Error: {result_final['detail']}")
        else:
            st.metric("Query Time", f"{result_final['query_time_ms']:.2f} ms")
            st.metric("Clean Rows (deduplicated)", result_final['count'])

    # --- Show Difference ---
    if "error" not in result_raw and "error" not in result_final:
        diff = result_raw['count'] - result_final['count']
        st.warning(f"**Benchmark Result:** {diff} duplicate/old rows were cleaned up by `ReplacingMergeTree`.")

st.divider()

# --- 3. Live Data Placeholder ---
st.header("3. (Future) Real-Time 'Hot Path' Data")
st.write("This section would call the `/realtime/book-depth` endpoint, which would query the in-memory Segment Tree (not ClickHouse).")
if st.button("Get Live Book Depth (Placeholder)"):
    with st.spinner("Calling hot path..."):
        params = {"symbol": symbol}
        result = fetch_api_data("/realtime/book-depth", params)
        st.json(result)