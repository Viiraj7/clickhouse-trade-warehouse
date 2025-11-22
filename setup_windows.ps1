# Complete setup and initialization for Windows
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "ClickHouse Trade Warehouse - Complete Setup" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Step 1: Clean slate
Write-Host "`n[1/6] Stopping and cleaning existing containers..." -ForegroundColor Yellow
docker-compose down -v
Start-Sleep -Seconds 3

# Step 2: Start containers
Write-Host "`n[2/6] Starting Docker containers..." -ForegroundColor Yellow
docker-compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Failed to start Docker containers!" -ForegroundColor Red
    exit 1
}

# Step 3: Wait for health
Write-Host "`n[3/6] Waiting for containers to be healthy (120 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 120

Write-Host "`nContainer Status:" -ForegroundColor Cyan
docker-compose ps

# Step 4: Test connectivity
Write-Host "`n[4/6] Testing ClickHouse connectivity..." -ForegroundColor Yellow
$retries = 0
$maxRetries = 10
$connected = $false

while ($retries -lt $maxRetries -and -not $connected) {
    $result = docker exec clickhouse-01 clickhouse-client --query "SELECT 1" 2>&1
    if ($result -eq "1") {
        Write-Host "  [✓] ClickHouse is responding!" -ForegroundColor Green
        $connected = $true
        break
    }
    $retries++
    Write-Host "  Attempt $retries/$maxRetries..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
}

if (-not $connected) {
    Write-Host "`n[ERROR] Could not connect to ClickHouse!" -ForegroundColor Red
    Write-Host "Wait 2-3 more minutes and try again." -ForegroundColor Yellow
    exit 1
}

# Step 5: Initialize schema
Write-Host "`n[5/6] Initializing ClickHouse schema..." -ForegroundColor Yellow

$sqlFiles = @(
    @{ file = "sql_schema\01_ticks_local.sql"; name = "ticks_local" },
    @{ file = "sql_schema\02_ticks_kafka.sql"; name = "ticks_kafka" },
    @{ file = "sql_schema\04_ticks_buffer.sql"; name = "ticks_buffer" },
    @{ file = "sql_schema\03_kafka_to_buffer_mv.sql"; name = "kafka_to_buffer_mv" },
    @{ file = "sql_schema\05_ticks_all.sql"; name = "ticks_all" },
    @{ file = "sql_schema\06_ticks_dedup.sql"; name = "ticks_dedup" },
    @{ file = "sql_schema\07_trades_1m_agg.sql"; name = "trades_1m_agg" },
    @{ file = "sql_schema\08_trades_1m_mv.sql"; name = "trades_1m_mv" },
    @{ file = "sql_schema\09_local_to_dedup_mv.sql"; name = "local_to_dedup_mv" }
)

$successCount = 0
$failedTables = @()

foreach ($item in $sqlFiles) {
    $file = $item.file
    $name = $item.name
    
    Write-Host "  Creating $name..." -ForegroundColor Cyan -NoNewline
    
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        $output = $content | docker exec -i clickhouse-01 clickhouse-client --multiquery 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host " [✓]" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host " [✗]" -ForegroundColor Red
            Write-Host "    Error: $output" -ForegroundColor Red
            $failedTables += $name
        }
    } else {
        Write-Host " [✗] File not found" -ForegroundColor Red
        $failedTables += $name
    }
}

# Step 6: Verify
Write-Host "`n[6/6] Verifying installation..." -ForegroundColor Yellow
Write-Host "`nTables created:" -ForegroundColor Cyan
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"

# Summary
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Setup Summary" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if ($successCount -eq $sqlFiles.Count) {
    Write-Host "`n[SUCCESS] All $successCount tables created successfully!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Start data producer:  cd data_producer; python producer.py" -ForegroundColor White
    Write-Host "  2. Start API server:     cd api; python -m uvicorn main:app --reload" -ForegroundColor White
    Write-Host "  3. Start dashboard:      cd dashboard; python -m streamlit run streamlit_app.py" -ForegroundColor White
    Write-Host "`nDashboard will be at:     http://localhost:8501" -ForegroundColor Cyan
    Write-Host "API docs will be at:      http://localhost:8000/docs" -ForegroundColor Cyan
} else {
    Write-Host "`n[WARNING] Only $successCount/$($sqlFiles.Count) tables created successfully" -ForegroundColor Yellow
    if ($failedTables.Count -gt 0) {
        Write-Host "`nFailed tables:" -ForegroundColor Red
        foreach ($table in $failedTables) {
            Write-Host "  - $table" -ForegroundColor Red
        }
        Write-Host "`nTry running this script again in 2-3 minutes." -ForegroundColor Yellow
    }
}

Write-Host "`n================================================================" -ForegroundColor Cyan
