@echo off
REM ============================================================================
REM Comprehensive Setup Script for ClickHouse Trade Analytics Warehouse
REM ============================================================================
REM This script will:
REM 1. Check prerequisites (Docker, Python)
REM 2. Create .env file from .env.example
REM 3. Start Docker infrastructure (ClickHouse + Kafka)
REM 4. Wait for services to be ready
REM 5. Initialize ClickHouse schema
REM 6. Install Python dependencies for all services
REM 7. Verify the setup
REM ============================================================================

echo.
echo ============================================================================
echo  ClickHouse Trade Analytics Warehouse - Setup Script
echo ============================================================================
echo.

REM Step 1: Check Prerequisites
echo [1/8] Checking prerequisites...
echo.

REM Check Docker
docker --version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Docker is not installed or not in PATH.
    echo Please install Docker Desktop from https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)
echo   ✓ Docker found

REM Check Python
python --version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Python is not installed or not in PATH.
    echo Please install Python 3.8+ from https://www.python.org/downloads/
    pause
    exit /b 1
)
echo   ✓ Python found

REM Check pip
pip --version >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: pip is not installed or not in PATH.
    pause
    exit /b 1
)
echo   ✓ pip found
echo.

REM Step 2: Create .env file
echo [2/8] Creating .env file from template...
if not exist .env (
    copy .env.example .env
    echo   ✓ .env file created
) else (
    echo   ✓ .env file already exists
)
echo.

REM Step 3: Stop any existing containers
echo [3/8] Stopping any existing containers...
docker-compose down >nul 2>&1
echo   ✓ Cleanup complete
echo.

REM Step 4: Start Docker Infrastructure
echo [4/8] Starting Docker infrastructure (ClickHouse + Kafka)...
echo   This may take 1-2 minutes on first run (pulling images)...
echo.
docker-compose up -d
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to start Docker containers.
    echo Please check Docker Desktop is running.
    pause
    exit /b 1
)
echo   ✓ Docker containers started
echo.

REM Step 5: Wait for services to be ready
echo [5/8] Waiting for services to be ready...
echo   Waiting for ClickHouse (60 seconds)...
timeout /t 60 /nobreak >nul

REM Check if ClickHouse is responding
echo   Testing ClickHouse connection...
set "clickhouse_ready=0"
for /L %%i in (1,1,30) do (
    curl -s http://localhost:8123/ping >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "clickhouse_ready=1"
        goto clickhouse_ready
    )
    timeout /t 2 /nobreak >nul
)
:clickhouse_ready

if "%clickhouse_ready%"=="0" (
    echo WARNING: ClickHouse may not be fully ready. Continuing anyway...
) else (
    echo   ✓ ClickHouse is ready
)
echo.

REM Step 6: Initialize ClickHouse Schema
echo [6/8] Initializing ClickHouse schema...
echo   Creating cluster configuration...

REM Run init_cluster.sql
docker exec clickhouse-01 clickhouse-client --multiquery < config\clickhouse\init_cluster.sql
if %ERRORLEVEL% neq 0 (
    echo WARNING: Failed to initialize cluster. Continuing anyway...
) else (
    echo   ✓ Cluster initialized
)

echo   Creating analytics tables...
REM Create database and tables
docker exec clickhouse-01 clickhouse-client -q "CREATE DATABASE IF NOT EXISTS default"

REM Run each SQL file individually
for %%f in (sql_schema\*.sql) do (
    if not "%%~nxf"=="all.sql" (
        echo   - Creating %%~nxf...
        docker exec -i clickhouse-01 clickhouse-client --multiquery < "%%f"
    )
)
echo   ✓ Schema initialized
echo.

REM Step 7: Install Python Dependencies
echo [7/8] Installing Python dependencies...
echo.

echo   Installing data_producer dependencies...
cd data_producer
pip install -r requirements.txt >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo WARNING: Some data_producer dependencies may have failed to install
) else (
    echo   ✓ data_producer dependencies installed
)
cd ..

echo   Installing API dependencies...
cd api
pip install -r requirements.txt >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo WARNING: Some API dependencies may have failed to install
) else (
    echo   ✓ API dependencies installed
)
cd ..

echo   Installing dashboard dependencies...
cd dashboard
pip install -r requirements.txt >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo WARNING: Some dashboard dependencies may have failed to install
) else (
    echo   ✓ dashboard dependencies installed
)
cd ..
echo.

REM Step 8: Verify Setup
echo [8/8] Verifying setup...
echo.

REM Check Docker containers
docker ps --format "table {{.Names}}\t{{.Status}}" | findstr /C:"clickhouse" /C:"kafka"
echo.

echo ============================================================================
echo  Setup Complete!
echo ============================================================================
echo.
echo Next steps:
echo.
echo 1. Start the Data Producer (generates sample trade data):
echo    cd data_producer
echo    python producer.py
echo.
echo 2. Start the API Server (in a new terminal):
echo    cd api
echo    uvicorn main:app --reload
echo.
echo 3. Start the Dashboard (in a new terminal):
echo    cd dashboard
echo    streamlit run streamlit_app.py
echo.
echo 4. Access the dashboard:
echo    Open http://localhost:8501 in your browser
echo.
echo 5. Access the API docs:
echo    Open http://localhost:8000/docs in your browser
echo.
echo Services:
echo   - ClickHouse HTTP: http://localhost:8123
echo   - ClickHouse Native: localhost:9000
echo   - Kafka: localhost:29092
echo   - API Server: http://localhost:8000
echo   - Dashboard: http://localhost:8501
echo.
echo ============================================================================
echo.
pause
