# Diagnostic script
Write-Host "=== Checking ClickHouse Keeper ===" -ForegroundColor Cyan
docker exec clickhouse-keeper cat /var/log/clickhouse-keeper/clickhouse-keeper.log
Write-Host ""
Write-Host "=== Checking ClickHouse Keeper Error Log ===" -ForegroundColor Cyan
docker exec clickhouse-keeper cat /var/log/clickhouse-keeper/clickhouse-keeper.err.log
Write-Host ""
Write-Host "=== Testing ClickHouse Server Connection ===" -ForegroundColor Cyan
docker exec clickhouse-01 clickhouse-client --query "SELECT 1"
Write-Host ""
Write-Host "=== Testing keeper-cli ===" -ForegroundColor Cyan
docker exec clickhouse-keeper clickhouse-keeper-cli --host localhost --port 9181 --command "stat /"
Write-Host ""
Write-Host "=== Checking ClickHouse Server Logs ===" -ForegroundColor Cyan
docker exec clickhouse-01 tail -50 /var/log/clickhouse-server/clickhouse-server.log
