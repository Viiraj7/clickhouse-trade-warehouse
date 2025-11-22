# Refresh Aggregations - Run this before benchmarking
Write-Host "`nRefreshing aggregation tables..." -ForegroundColor Yellow

Write-Host "  Clearing old aggregations..." -ForegroundColor Gray
docker exec clickhouse-01 clickhouse-client -q "TRUNCATE TABLE default.trades_1m_agg"

Write-Host "  Rebuilding from ticks_all..." -ForegroundColor Gray
docker exec clickhouse-01 clickhouse-client --multiquery "
INSERT INTO default.trades_1m_agg 
SELECT 
    symbol, 
    toStartOfMinute(event_time) AS minute,
    argMinState(price, event_time) AS open,
    maxState(price) AS high,
    minState(price) AS low,
    argMaxState(price, event_time) AS close,
    sumState(size) AS volume,
    sumState(price * size) AS vwap_pv
FROM default.ticks_all 
WHERE event_type = 'trade' 
GROUP BY symbol, minute;
"

$count = docker exec clickhouse-01 clickhouse-client -q "SELECT COUNT() FROM default.trades_1m_agg"
Write-Host "`n✅ Aggregation table refreshed: $count bars" -ForegroundColor Green
Write-Host "💡 Fast queries will now return correct results`n" -ForegroundColor Cyan
