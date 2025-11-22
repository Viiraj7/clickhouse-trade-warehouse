# ClickHouse Trade Warehouse - Startup Script
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Starting ClickHouse Trade Warehouse" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Cyan

# Step 1: Start Docker containers
Write-Host "Step 1: Starting Docker containers..." -ForegroundColor Yellow
docker-compose up -d
Start-Sleep -Seconds 15

# Step 2: Verify ClickHouse is ready
Write-Host "`nStep 2: Checking ClickHouse..." -ForegroundColor Yellow
$ready = $false
for ($i = 1; $i -le 5; $i++) {
    try {
        $result = docker exec clickhouse-01 clickhouse-client -q "SELECT 1"
        if ($result -eq "1") {
            Write-Host "✅ ClickHouse is ready" -ForegroundColor Green
            $ready = $true
            break
        }
    } catch {
        Write-Host "Waiting for ClickHouse... ($i/5)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

if (-not $ready) {
    Write-Host "❌ ClickHouse failed to start" -ForegroundColor Red
    exit 1
}

# Step 3: Check if tables exist
Write-Host "`nStep 3: Checking tables..." -ForegroundColor Yellow
$tableCount = docker exec clickhouse-01 clickhouse-client -q "SELECT count() FROM system.tables WHERE database='default'"
if ($tableCount -eq "0") {
    Write-Host "No tables found. Creating schema..." -ForegroundColor Yellow
    python init_clickhouse.py
} else {
    Write-Host "✅ Found $tableCount tables" -ForegroundColor Green
}

# Step 4: Get current data stats
Write-Host "`nStep 4: Current data statistics..." -ForegroundColor Yellow
$tickCount = docker exec clickhouse-01 clickhouse-client -q "SELECT formatReadableQuantity(COUNT()) FROM default.ticks_all"
$aggCount = docker exec clickhouse-01 clickhouse-client -q "SELECT COUNT() FROM default.trades_1m_agg"
Write-Host "  Ticks in database: $tickCount" -ForegroundColor Cyan
Write-Host "  Aggregated bars: $aggCount" -ForegroundColor Cyan

# Step 5: Start services
Write-Host "`nStep 5: Starting services..." -ForegroundColor Yellow

# Start API
Write-Host "  Starting API server..." -ForegroundColor Gray
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD'; Write-Host 'API Server' -ForegroundColor Green; python -m uvicorn api.main:app --host 0.0.0.0 --port 8000"
Start-Sleep -Seconds 3

# Start Dashboard
Write-Host "  Starting dashboard..." -ForegroundColor Gray
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD\dashboard'; Write-Host 'Streamlit Dashboard' -ForegroundColor Green; python -m streamlit run streamlit_app.py"
Start-Sleep -Seconds 3

# Start Data Producer
Write-Host "  Starting data producer..." -ForegroundColor Gray
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD\data_producer'; Write-Host 'Data Producer (2000 ticks/sec)' -ForegroundColor Green; python producer.py"

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  ✅ ALL SERVICES STARTED" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "`n📊 URLs:" -ForegroundColor Yellow
Write-Host "  API:       http://localhost:8000" -ForegroundColor White
Write-Host "  Dashboard: http://localhost:8501" -ForegroundColor White
Write-Host "`n💡 Tip: Data is accumulating in the background." -ForegroundColor Gray
Write-Host "    Close the producer window to stop generating data.`n" -ForegroundColor Gray
