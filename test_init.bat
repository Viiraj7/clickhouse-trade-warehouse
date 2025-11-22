@echo off
echo Testing ClickHouse connection...
docker exec clickhouse-01 clickhouse-client --query "SELECT 1"

echo.
echo Checking Keeper logs...
docker logs clickhouse-keeper 2>&1 | findstr "Listening"

echo.
echo Testing cluster query...
docker exec clickhouse-01 clickhouse-client --query "SELECT * FROM system.clusters WHERE cluster='analytics_cluster'"

echo.
echo Initializing schema - ticks_local...
type sql_schema\01_ticks_local.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery

echo.
echo Done! Check for errors above.
