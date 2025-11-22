import streamlit as st
import requests
import pandas as pd
import plotly.graph_objects as go
import time
import os
from datetime import datetime
from pathlib import Path
import csv

# --- Page Configuration ---
st.set_page_config(
    page_title="ClickHouse Trade Analytics",
    page_icon="⚡",
    layout="wide"
)

# --- API Configuration ---
API_BASE_URL = "http://localhost:8000"

# --- Results Directory ---
RESULTS_DIR = Path("../results")
RESULTS_DIR.mkdir(exist_ok=True)
BENCHMARK_CSV = RESULTS_DIR / "benchmark.csv"
COMPRESSION_TXT = RESULTS_DIR / "compression_stats.txt"

# --- Helper Functions ---

def save_benchmark_result(query_type: str, symbol: str, query_time_ms: float, rows_returned: int = 0, total_rows: int = 0):
    """Save benchmark result to CSV."""
    file_exists = BENCHMARK_CSV.exists()
    
    with open(BENCHMARK_CSV, 'a', newline='') as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(['timestamp', 'query_type', 'symbol', 'query_time_ms', 'rows_returned', 'total_rows', 'speedup'])
        
        writer.writerow([
            datetime.now().isoformat(),
            query_type,
            symbol,
            round(query_time_ms, 2),
            rows_returned,
            total_rows,
            ''  # speedup calculated later
        ])

def load_benchmark_history():
    """Load benchmark history from CSV."""
    if BENCHMARK_CSV.exists():
        try:
            df = pd.read_csv(BENCHMARK_CSV)
            return df
        except:
            return pd.DataFrame()
    return pd.DataFrame()

def fetch_api_data(endpoint: str, params: dict):
    """Helper function to call our FastAPI and return the JSON response."""
    try:
        response = requests.get(f"{API_BASE_URL}{endpoint}", params=params, timeout=60)
        response.raise_for_status()
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

# --- Sidebar for Navigation ---
st.sidebar.title("Navigation")
page = st.sidebar.radio(
    "Choose a page:",
    ["Benchmarks", "Query Tester", "History", "Compression Stats"]
)

if page == "Benchmarks":
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
    
    # Store results for comparison
    slow_result = None
    fast_result = None
    
    col_slow, col_fast = st.columns(2)
    
    # --- Run Slow Query ---
    with col_slow:
        if st.button("Run SLOW Query (Raw Scan)", type="secondary", use_container_width=True):
            with st.spinner(f"Running slow query for {symbol}..."):
                params = {"symbol": symbol, "limit": limit}
                slow_result = fetch_api_data("/backtest/slow", params)
                
            if "error" in slow_result:
                st.error(f"Error: {slow_result['detail']}")
            else:
                st.metric("Query Time", f"{slow_result['query_time_ms']:.2f} ms")
                st.metric("Rows Returned", slow_result['rows_returned'])
                
                # Save result
                save_benchmark_result("slow", symbol, slow_result['query_time_ms'], slow_result['rows_returned'])
                st.success("✅ Result saved to benchmark.csv")
                
                with st.expander("Show Chart"):
                    fig = create_candlestick_chart(slow_result.get('data', []))
                    st.plotly_chart(fig, use_container_width=True)
    
    # --- Run Fast Query ---
    with col_fast:
        if st.button("Run FAST Query (Rollup)", type="primary", use_container_width=True):
            with st.spinner(f"Running fast query for {symbol}..."):
                params = {"symbol": symbol, "limit": limit}
                fast_result = fetch_api_data("/backtest/fast", params)
                
            if "error" in fast_result:
                st.error(f"Error: {fast_result['detail']}")
            else:
                st.metric("Query Time", f"{fast_result['query_time_ms']:.2f} ms")
                st.metric("Rows Returned", fast_result['rows_returned'])
                
                # Save result
                save_benchmark_result("fast", symbol, fast_result['query_time_ms'], fast_result['rows_returned'])
                st.success("✅ Result saved to benchmark.csv")
                
                with st.expander("Show Chart"):
                    fig = create_candlestick_chart(fast_result.get('data', []))
                    st.plotly_chart(fig, use_container_width=True)
    
    # --- Compare Results ---
    if slow_result and fast_result and "error" not in slow_result and "error" not in fast_result:
        st.divider()
        st.subheader("📊 Speedup Comparison")
        speedup = slow_result['query_time_ms'] / fast_result['query_time_ms']
        col1, col2, col3 = st.columns(3)
        with col1:
            st.metric("Slow Query", f"{slow_result['query_time_ms']:.2f} ms")
        with col2:
            st.metric("Fast Query", f"{fast_result['query_time_ms']:.2f} ms")
        with col3:
            st.metric("Speedup", f"{speedup:.1f}x", delta=f"{((speedup-1)*100):.0f}% faster")
    
    st.divider()
    
    # --- 2. Deduplication Benchmark Section ---
    st.header("2. Deduplication Benchmark (`ReplacingMergeTree`)")
    st.write("This tests the difference between a simple `COUNT()` vs. a `COUNT() ... FINAL` on our deduplication table.")
    
    dedup_symbol = st.text_input("Enter Symbol:", "AAPL", key="dedup_symbol").upper()
    
    if st.button("Run Deduplication Benchmark"):
        col_raw, col_final = st.columns(2)
        
        with col_raw:
            st.subheader("Raw Count (Fast, Unclean)")
            with st.spinner("Getting raw count..."):
                params = {"symbol": dedup_symbol}
                result_raw = fetch_api_data("/dedup/raw_count", params)
            
            if "error" in result_raw:
                st.error(f"Error: {result_raw['detail']}")
            else:
                st.metric("Query Time", f"{result_raw['query_time_ms']:.2f} ms")
                st.metric("Total Rows (with duplicates)", f"{result_raw['count']:,}")
        
        with col_final:
            st.subheader("Final Count (Slower, Clean)")
            with st.spinner("Getting FINAL count..."):
                params = {"symbol": dedup_symbol}
                result_final = fetch_api_data("/dedup/final_count", params)
            
            if "error" in result_final:
                st.error(f"Error: {result_final['detail']}")
            else:
                st.metric("Query Time", f"{result_final['query_time_ms']:.2f} ms")
                st.metric("Clean Rows (deduplicated)", f"{result_final['count']:,}")
        
        if "error" not in result_raw and "error" not in result_final:
            diff = result_raw['count'] - result_final['count']
            speedup = result_final['query_time_ms'] / result_raw['query_time_ms']
            st.warning(f"**Result:** {diff:,} duplicates removed. FINAL is {speedup:.1f}x slower but accurate.")
            
            # Save results
            save_benchmark_result("dedup_raw", dedup_symbol, result_raw['query_time_ms'], 0, result_raw['count'])
            save_benchmark_result("dedup_final", dedup_symbol, result_final['query_time_ms'], 0, result_final['count'])

elif page == "Query Tester":
    st.header("🔍 Custom Query Tester")
    st.write("Test any ClickHouse query and see results. Results are automatically saved.")
    
    # Load example queries
    example_queries = {
        "Count rows in ticks_local": "SELECT count() FROM default.ticks_local",
        "Count rows in trades_1m_agg": "SELECT count() FROM default.trades_1m_agg",
        "Latest 10 trades": "SELECT * FROM default.ticks_local ORDER BY event_time DESC LIMIT 10",
        "Price stats by symbol": """
SELECT 
    symbol,
    min(price) AS min_price,
    max(price) AS max_price,
    avg(price) AS avg_price,
    count() AS trade_count
FROM default.ticks_local
WHERE event_type = 'trade'
GROUP BY symbol
ORDER BY trade_count DESC
        """,
        "Volume by symbol": """
SELECT 
    symbol,
    sum(size) AS total_volume
FROM default.ticks_local
WHERE event_type = 'trade'
GROUP BY symbol
ORDER BY total_volume DESC
        """
    }
    
    selected_example = st.selectbox("Or choose an example query:", [""] + list(example_queries.keys()))
    
    if selected_example:
        query = st.text_area("SQL Query:", value=example_queries[selected_example], height=200)
    else:
        query = st.text_area("SQL Query:", height=200, placeholder="Enter your ClickHouse SQL query here...")
    
    if st.button("Execute Query", type="primary"):
        if not query.strip():
            st.error("Please enter a query")
        else:
            with st.spinner("Executing query..."):
                start_time = time.perf_counter()
                try:
                    # Call API with custom query
                    response = requests.post(
                        f"{API_BASE_URL}/query/custom",
                        json={"query": query},
                        timeout=60
                    )
                    response.raise_for_status()
                    result = response.json()
                    elapsed = (time.perf_counter() - start_time) * 1000
                    
                    if "error" in result:
                        st.error(f"Error: {result['detail']}")
                    else:
                        st.success(f"✅ Query executed in {elapsed:.2f} ms")
                        
                        # Display results
                        if result.get('data'):
                            df = pd.DataFrame(result['data'])
                            st.dataframe(df, use_container_width=True)
                            
                            # Save result
                            save_benchmark_result("custom", "N/A", elapsed, len(df), 0)
                            
                            # Download button
                            csv = df.to_csv(index=False)
                            st.download_button(
                                label="Download Results as CSV",
                                data=csv,
                                file_name=f"query_result_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv",
                                mime="text/csv"
                            )
                        else:
                            st.info("Query executed successfully but returned no data.")
                            
                except requests.exceptions.ConnectionError:
                    st.error("Could not connect to API. Make sure it's running on http://localhost:8000")
                except Exception as e:
                    st.error(f"Error: {str(e)}")

elif page == "History":
    st.header("📈 Benchmark History")
    st.write("View all saved benchmark results")
    
    df = load_benchmark_history()
    
    if df.empty:
        st.info("No benchmark results yet. Run some queries to see history here.")
    else:
        # Calculate speedups
        if 'speedup' in df.columns:
            df['speedup'] = pd.to_numeric(df['speedup'], errors='coerce')
        
        # Show summary
        st.subheader("Summary Statistics")
        col1, col2, col3, col4 = st.columns(4)
        
        with col1:
            st.metric("Total Queries", len(df))
        with col2:
            if 'query_time_ms' in df.columns:
                st.metric("Avg Query Time", f"{df['query_time_ms'].mean():.2f} ms")
        with col3:
            slow_queries = df[df['query_type'] == 'slow']
            if not slow_queries.empty:
                st.metric("Avg Slow Query", f"{slow_queries['query_time_ms'].mean():.2f} ms")
        with col4:
            fast_queries = df[df['query_type'] == 'fast']
            if not fast_queries.empty:
                st.metric("Avg Fast Query", f"{fast_queries['query_time_ms'].mean():.2f} ms")
        
        # Show full table
        st.subheader("All Results")
        st.dataframe(df, use_container_width=True)
        
        # Download button
        csv = df.to_csv(index=False)
        st.download_button(
            label="Download Full History as CSV",
            data=csv,
            file_name=f"benchmark_history_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv",
            mime="text/csv"
        )
        
        # Charts
        if len(df) > 1:
            st.subheader("Query Time Trends")
            df['timestamp'] = pd.to_datetime(df['timestamp'])
            fig = go.Figure()
            
            for query_type in df['query_type'].unique():
                type_df = df[df['query_type'] == query_type]
                fig.add_trace(go.Scatter(
                    x=type_df['timestamp'],
                    y=type_df['query_time_ms'],
                    mode='lines+markers',
                    name=query_type
                ))
            
            fig.update_layout(
                title="Query Time Over Time",
                xaxis_title="Time",
                yaxis_title="Query Time (ms)",
                template="plotly_dark"
            )
            st.plotly_chart(fig, use_container_width=True)

elif page == "Compression Stats":
    st.header("💾 Compression Statistics")
    st.write("View and update compression statistics for ClickHouse tables")
    
    if st.button("Fetch Compression Stats"):
        with st.spinner("Fetching compression statistics..."):
            try:
                response = requests.get(f"{API_BASE_URL}/stats/compression", timeout=30)
                response.raise_for_status()
                result = response.json()
                
                if "error" in result:
                    st.error(f"Error: {result['detail']}")
                else:
                    st.success("✅ Compression stats fetched")
                    
                    if result.get('data'):
                        df = pd.DataFrame(result['data'])
                        st.dataframe(df, use_container_width=True)
                        
                        # Save to file
                        with open(COMPRESSION_TXT, 'w') as f:
                            f.write("# ClickHouse Compression Statistics\n")
                            f.write(f"# Generated: {datetime.now().isoformat()}\n\n")
                            f.write(df.to_string(index=False))
                        
                        st.success("✅ Stats saved to compression_stats.txt")
            except Exception as e:
                st.error(f"Error: {str(e)}")
    
    # Show existing stats
    if COMPRESSION_TXT.exists():
        st.subheader("Saved Compression Stats")
        with open(COMPRESSION_TXT, 'r') as f:
            st.code(f.read())
