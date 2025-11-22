#!/usr/bin/env python3
"""
Automated Test Queries for Cold Path
Run this script to test all queries and save results
"""
import requests
import time
import csv
from datetime import datetime
from pathlib import Path

API_BASE_URL = "http://localhost:8000"
RESULTS_DIR = Path("results")
RESULTS_DIR.mkdir(exist_ok=True)

def test_endpoint(endpoint, params=None, description=""):
    """Test an API endpoint and return results."""
    print(f"\n[TEST] {description}")
    print(f"  Endpoint: {endpoint}")
    
    try:
        start = time.perf_counter()
        response = requests.get(f"{API_BASE_URL}{endpoint}", params=params, timeout=60)
        elapsed = (time.perf_counter() - start) * 1000
        
        if response.status_code == 200:
            result = response.json()
            if "error" not in result:
                print(f"  ✅ Success: {result.get('query_time_ms', elapsed):.2f} ms")
                return result
            else:
                print(f"  ❌ Error: {result.get('detail', 'Unknown error')}")
        else:
            print(f"  ❌ HTTP {response.status_code}: {response.text}")
    except requests.exceptions.ConnectionError:
        print(f"  ❌ Connection Error: API not running at {API_BASE_URL}")
    except Exception as e:
        print(f"  ❌ Error: {str(e)}")
    
    return None

def save_result(query_type, symbol, query_time_ms, rows_returned=0, total_rows=0):
    """Save test result to CSV."""
    csv_file = RESULTS_DIR / "benchmark.csv"
    file_exists = csv_file.exists()
    
    with open(csv_file, 'a', newline='') as f:
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
            ''
        ])

def main():
    print("=" * 70)
    print("COLD PATH AUTOMATED TEST SUITE")
    print("=" * 70)
    print(f"API URL: {API_BASE_URL}")
    print(f"Results will be saved to: {RESULTS_DIR}")
    
    # Test symbols
    symbols = ["AAPL", "GOOG", "MSFT", "TSLA"]
    
    print("\n" + "=" * 70)
    print("1. TESTING SLOW QUERIES (Raw Scan)")
    print("=" * 70)
    
    slow_results = {}
    for symbol in symbols:
        result = test_endpoint(
            "/backtest/slow",
            {"symbol": symbol, "limit": 100},
            f"Slow query for {symbol}"
        )
        if result:
            slow_results[symbol] = result
            save_result("slow", symbol, result['query_time_ms'], result.get('rows_returned', 0))
    
    print("\n" + "=" * 70)
    print("2. TESTING FAST QUERIES (Rollup)")
    print("=" * 70)
    
    fast_results = {}
    for symbol in symbols:
        result = test_endpoint(
            "/backtest/fast",
            {"symbol": symbol, "limit": 100},
            f"Fast query for {symbol}"
        )
        if result:
            fast_results[symbol] = result
            save_result("fast", symbol, result['query_time_ms'], result.get('rows_returned', 0))
    
    print("\n" + "=" * 70)
    print("3. CALCULATING SPEEDUP")
    print("=" * 70)
    
    for symbol in symbols:
        if symbol in slow_results and symbol in fast_results:
            slow_time = slow_results[symbol]['query_time_ms']
            fast_time = fast_results[symbol]['query_time_ms']
            speedup = slow_time / fast_time if fast_time > 0 else 0
            print(f"  {symbol}: {slow_time:.2f} ms → {fast_time:.2f} ms = {speedup:.1f}x speedup")
    
    print("\n" + "=" * 70)
    print("4. TESTING DEDUPLICATION")
    print("=" * 70)
    
    for symbol in symbols:
        raw_result = test_endpoint(
            "/dedup/raw_count",
            {"symbol": symbol},
            f"Raw count for {symbol}"
        )
        if raw_result:
            save_result("dedup_raw", symbol, raw_result['query_time_ms'], 0, raw_result.get('count', 0))
        
        final_result = test_endpoint(
            "/dedup/final_count",
            {"symbol": symbol},
            f"Final count for {symbol}"
        )
        if final_result:
            save_result("dedup_final", symbol, final_result['query_time_ms'], 0, final_result.get('count', 0))
        
        if raw_result and final_result:
            diff = raw_result.get('count', 0) - final_result.get('count', 0)
            print(f"  {symbol}: {diff:,} duplicates removed")
    
    print("\n" + "=" * 70)
    print("5. TESTING COMPRESSION STATS")
    print("=" * 70)
    
    result = test_endpoint("/stats/compression", None, "Compression statistics")
    if result and result.get('data'):
        print(f"  Found compression stats for {len(result['data'])} columns")
    
    print("\n" + "=" * 70)
    print("TEST SUITE COMPLETE")
    print("=" * 70)
    print(f"Results saved to: {RESULTS_DIR / 'benchmark.csv'}")
    print("\nNext steps:")
    print("1. View results in dashboard: streamlit run dashboard/streamlit_app.py")
    print("2. Check benchmark.csv for detailed results")

if __name__ == "__main__":
    main()

