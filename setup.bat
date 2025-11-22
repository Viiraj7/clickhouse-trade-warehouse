@echo off
REM Complete setup script for Windows
echo ================================================================
echo ClickHouse Trade Warehouse - Complete Setup
echo ================================================================

echo.
echo [1/6] Stopping any existing containers...
docker-compose down -v
timeout /t 3 /nobreak >nul

echo.
echo [2/6] Starting Docker containers...
docker-compose up -d
if %errorlevel% neq 0 (
    echo ERROR: Failed to start Docker containers
    pause
    exit /b 1
)

echo.
echo [3/6] Waiting for containers to be healthy (120 seconds)...
echo ClickHouse Keeper needs time to start properly...
timeout /t 120 /nobreak >nul

echo.
echo Container Status:
docker-compose ps

echo.
echo [4/6] Testing ClickHouse connectivity...
set /a retries=0
:retry_loop
if %retries% GEQ 10 goto connect_failed
docker exec clickhouse-01 clickhouse-client --query "SELECT 1" >nul 2>&1
if %errorlevel% EQU 0 goto connected
set /a retries+=1
echo   Attempt %retries%/10...
timeout /t 3 /nobreak >nul
goto retry_loop

:connected
echo   [OK] ClickHouse is responding!

echo.
echo [5/6] Initializing ClickHouse schema...
echo    [1/9] Creating ticks_local table...
type sql_schema\01_ticks_local.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [2/9] Creating ticks_kafka table...
type sql_schema\02_ticks_kafka.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [3/9] Creating ticks_buffer table...
type sql_schema\04_ticks_buffer.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [4/9] Creating kafka_to_buffer_mv...
type sql_schema\03_kafka_to_buffer_mv.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [5/9] Creating ticks_all distributed table...
type sql_schema\05_ticks_all.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [6/9] Creating ticks_dedup table...
type sql_schema\06_ticks_dedup.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [7/9] Creating trades_1m_agg table...
type sql_schema\07_trades_1m_agg.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [8/9] Creating trades_1m_mv...
type sql_schema\08_trades_1m_mv.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo    [9/9] Creating local_to_dedup_mv...
type sql_schema\09_local_to_dedup_mv.sql | docker exec -i clickhouse-01 clickhouse-client --multiquery >nul 2>&1
if %errorlevel% EQU 0 (echo      [OK]) else (echo      [WARN] May already exist)

echo.
echo [6/6] Verifying tables were created...
echo.
echo Tables in ClickHouse:
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"

echo.
echo ================================================================
echo SUCCESS! Setup Complete!
echo ================================================================
echo.
echo You should see 9 tables listed above.
echo.
echo Next steps - Open 3 separate PowerShell windows:
echo.
echo   Window 1 - Data Producer:
echo     cd data_producer
echo     pip install -r requirements.txt
echo     python producer.py
echo.
echo   Window 2 - API Server:
echo     cd api
echo     pip install -r requirements.txt
echo     python -m uvicorn main:app --reload
echo.
echo   Window 3 - Dashboard:
echo     cd dashboard
echo     pip install -r requirements.txt
echo     python -m streamlit run streamlit_app.py
echo.
echo Then open:
echo   Dashboard: http://localhost:8501
echo   API docs:  http://localhost:8000/docs
echo.
echo ================================================================
pause
goto :eof

:connect_failed
echo.
echo [ERROR] Could not connect to ClickHouse!
echo ClickHouse Keeper may need more time to start.
echo Wait 2-3 more minutes and run setup.bat again.
pause
exit /b 1
