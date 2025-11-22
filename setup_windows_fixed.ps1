# Complete setup and initialization for Windows
# This script will:
# 1. Stop and clean all containers
# 2. Start fresh containers
# 3. Wait for them to be healthy
# 4. Initialize the ClickHouse schema
# 5. Verify everything is working

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

# Step 3: Wait for health - LONGER WAIT FOR KEEPER
Write-Host "`n[3/6] Waiting for containers to be healthy (120 seconds)..." -ForegroundColor Yellow
Write-Host "ClickHouse Keeper needs time to start and establish connections..." -ForegroundColor Gray
Start-Sleep -Seconds 120

Write-Host "`nContainer Status:" -ForegroundColor Cyan
docker-compose ps

# Step 4: Test connectivity
Write-Host "`n[4/6] Testing ClickHouse connectivity..." -ForegroundColor Yellow
$retries = 0
$maxRetries = 10
$connected = $false

while ($retries -lt $maxRetries -and -not $connected) {
    try {
        $result = docker exec clickhouse-01 clickhouse-client --query "SELECT 1" 2>&1
        if ($result -eq "1") {
            Write-Host "  [✓] ClickHouse is responding!" -ForegroundColor Green
            $connected = $true
            break
        }
    } catch {
        # Ignore errors and retry
    }
    $retries++
    Write-Host "  Attempt $retries/$maxRetries..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
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
        try {
            $content = Get-Content $file -Raw
            $output = $content | docker exec -i clickhouse-01 clickhouse-client --multiquery 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host " [✓]" -ForegroundColor Green
                $successCount++
            } else {
                Write-Host " [✗]" -ForegroundColor Red
                if ($output -match "already exists") {
                    Write-Host "    (Table already exists - this is OK)" -ForegroundColor Yellow
                    $successCount++
                } else {
                    Write-Host "    Error: $($output | Select-String -Pattern 'Exception' -Context 0,1)" -ForegroundColor Red
                    $failedTables += $name
                }
            }
        } catch {
            Write-Host " [✗]" -ForegroundColor Red
            Write-Host "    Error: $_" -ForegroundColor Red
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
    Write-Host "`n  Open 3 separate PowerShell terminals:" -ForegroundColor White
    Write-Host "`n  Terminal 1 - Data Producer:" -ForegroundColor Cyan
    Write-Host "    cd data_producer" -ForegroundColor White
    Write-Host "    pip install -r requirements.txt" -ForegroundColor White
    Write-Host "    python producer.py" -ForegroundColor White
    Write-Host "`n  Terminal 2 - API Server:" -ForegroundColor Cyan
    Write-Host "    cd api" -ForegroundColor White
    Write-Host "    pip install -r requirements.txt" -ForegroundColor White
    Write-Host "    python -m uvicorn main:app --reload" -ForegroundColor White
    Write-Host "`n  Terminal 3 - Dashboard:" -ForegroundColor Cyan
    Write-Host "    cd dashboard" -ForegroundColor White
    Write-Host "    pip install -r requirements.txt" -ForegroundColor White
    Write-Host "    python -m streamlit run streamlit_app.py" -ForegroundColor White
    Write-Host "`n  Then open:" -ForegroundColor Yellow
    Write-Host "    Dashboard: http://localhost:8501" -ForegroundColor Green
    Write-Host "    API docs:  http://localhost:8000/docs" -ForegroundColor Green
} else {
    Write-Host "`n[WARNING] Only $successCount/$($sqlFiles.Count) tables created successfully" -ForegroundColor Yellow
    if ($failedTables.Count -gt 0) {
        Write-Host "`nFailed tables:" -ForegroundColor Red
        foreach ($table in $failedTables) {
            Write-Host "  - $table" -ForegroundColor Red
        }
        Write-Host "`nThis usually means ClickHouse Keeper needs more time." -ForegroundColor Yellow
        Write-Host "Wait 2-3 minutes and run this script again." -ForegroundColor Yellow
    }
}

Write-Host "`n================================================================" -ForegroundColor Cyan
