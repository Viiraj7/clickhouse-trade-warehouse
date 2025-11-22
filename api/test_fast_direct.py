from clickhouse_driver import Client

client = Client(host='localhost', port=9000, settings={'use_query_cache': False})

query = """
SELECT
    minute,
    symbol,
    argMinMerge(trades_1m_agg.open) AS open,
    maxMerge(trades_1m_agg.high) AS high,
    minMerge(trades_1m_agg.low) AS low,
    argMaxMerge(trades_1m_agg.close) AS close,
    sumMerge(trades_1m_agg.volume) AS volume,
    sumMerge(trades_1m_agg.vwap_pv) / sumMerge(trades_1m_agg.volume) AS vwap
FROM default.trades_1m_agg
WHERE symbol = 'AAPL'
GROUP BY symbol, minute
ORDER BY minute DESC
LIMIT 3
"""

print("Testing fast query with table-qualified columns...")
result = client.execute(query)
print(f"Success! Got {len(result)} rows")
for row in result:
    print(row)
