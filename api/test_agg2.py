from clickhouse_driver import Client

# Test different query approaches
client = Client(host='localhost', port=9000)

print("Test 1: Select from table directly")
try:
    query = """
    SELECT 
        symbol,
        minute,
        argMinMerge(open) AS open,
        maxMerge(high) AS high,
        minMerge(low) AS low,
        argMaxMerge(close) AS close,
        sumMerge(volume) AS volume,
        sumMerge(vwap_pv) / sumMerge(volume) AS vwap
    FROM default.trades_1m_agg
    WHERE symbol = %(symbol)s
    GROUP BY symbol, minute
    ORDER BY minute DESC
    LIMIT %(limit)s
    """
    result = client.execute(query, {'symbol': 'AAPL', 'limit': 3})
    print(f"✓ Success: {len(result)} rows")
    for row in result:
        print(row)
except Exception as e:
    print(f"✗ Error: {e}")

print("\nTest 2: Query with explicit database.table")
try:
    query = """
    SELECT 
        symbol,
        minute,
        argMinMerge(trades_1m_agg.open) AS open,
        maxMerge(trades_1m_agg.high) AS high
    FROM default.trades_1m_agg
    WHERE symbol = %(symbol)s
    GROUP BY symbol, minute
    ORDER BY minute DESC
    LIMIT %(limit)s
    """
    result = client.execute(query, {'symbol': 'AAPL', 'limit': 3})
    print(f"✓ Success: {len(result)} rows")
except Exception as e:
    print(f"✗ Error: {e}")

print("\nTest 3: Subquery approach")
try:
    query = """
    SELECT 
        symbol,
        minute,
        argMinMerge(open) AS open,
        maxMerge(high) AS high
    FROM (
        SELECT * FROM default.trades_1m_agg WHERE symbol = %(symbol)s
    )
    GROUP BY symbol, minute
    ORDER BY minute DESC
    LIMIT %(limit)s
    """
    result = client.execute(query, {'symbol': 'AAPL', 'limit': 3})
    print(f"✓ Success: {len(result)} rows")
except Exception as e:
    print(f"✗ Error: {e}")
