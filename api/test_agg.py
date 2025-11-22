from clickhouse_driver import Client

c = Client('localhost', settings={'use_query_cache': False})
query = """
SELECT 
    minute, symbol,
    argMinMerge(open) AS open,
    maxMerge(high) AS high,
    minMerge(low) AS low,
    argMaxMerge(close) AS close,
    sumMerge(volume) AS volume,
    sumMerge(vwap_pv) / sumMerge(volume) AS vwap
FROM default.trades_1m_agg 
WHERE symbol = 'AAPL' 
GROUP BY symbol, minute 
ORDER BY minute DESC 
LIMIT 3
"""

try:
    result = c.execute(query)
    print(f"✓ Success! Got {len(result)} rows")
    for row in result:
        print(row)
except Exception as e:
    print(f"✗ Error: {e}")
