# PowerShell script to initialize ClickHouse schema on Windows
# Run: .\init_clickhouse_windows.ps1

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "ClickHouse Schema Initialization (Windows)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Check if containers are running
Write-Host "`n[1/3] Checking Docker containers..." -ForegroundColor Yellow
$containers = docker ps --format "{{.Names}}" | Where-Object { $_ -like "clickhouse*" -or $_ -like "kafka*" }
if ($containers.Count -lt 5) {
    Write-Host "  [ERROR] Not all containers are running. Run: docker-compose up -d" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Containers are running" -ForegroundColor Green

# Wait for keeper to be ready
Write-Host "`n[2/3] Waiting for ClickHouse Keeper to be ready..." -ForegroundColor Yellow
$maxWait = 120  # 2 minutes
$waited = 0
$keeperReady = $false

while ($waited -lt $maxWait -and -not $keeperReady) {
    try {
        $result = docker exec clickhouse-keeper clickhouse-keeper-cli --host localhost --port 9181 --command "stat /" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $keeperReady = $true
            Write-Host "  [OK] Keeper is ready!" -ForegroundColor Green
            break
        }
    } catch {
        # Keeper not ready yet
    }
    
    Start-Sleep -Seconds 5
    $waited += 5
    Write-Host "  Waiting... ($waited/$maxWait seconds)" -ForegroundColor Gray
}

if (-not $keeperReady) {
    Write-Host "  [WARNING] Keeper not ready after $maxWait seconds" -ForegroundColor Yellow
    Write-Host "  Will attempt initialization anyway..." -ForegroundColor Yellow
}

# Initialize schema
Write-Host "`n[3/3] Initializing ClickHouse schema..." -ForegroundColor Yellow

$sqlFiles = @(
    "sql_schema\01_ticks_local.sql",
    "sql_schema\02_ticks_kafka.sql",
    "sql_schema\04_ticks_buffer.sql",
    "sql_schema\03_kafka_to_buffer_mv.sql",
    "sql_schema\05_ticks_all.sql",
    "sql_schema\06_ticks_dedup.sql",
    "sql_schema\07_trades_1m_agg.sql",
    "sql_schema\08_trades_1m_mv.sql",
    "sql_schema\09_local_to_dedup_mv.sql"
)

$successCount = 0
$failedFiles = @()

foreach ($file in $sqlFiles) {
    if (Test-Path $file) {
        Write-Host "`n[INFO] Executing $file..." -ForegroundColor Yellow
        $content = Get-Content $file -Raw
        $content | docker exec -i clickhouse-01 clickhouse-client --multiquery 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $file executed successfully" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  [ERROR] Failed to execute $file" -ForegroundColor Red
            $failedFiles += $file
            
            # Show error details
            $content | docker exec -i clickhouse-01 clickhouse-client --multiquery 2>&1 | Select-Object -Last 5
        }
    } else {
        Write-Host "  [WARNING] File not found: $file" -ForegroundColor Yellow
    }
}

# Summary
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Initialization Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Successfully executed: $successCount/$($sqlFiles.Count)" -ForegroundColor $(if ($successCount -eq $sqlFiles.Count) { "Green" } else { "Yellow" })

if ($failedFiles.Count -gt 0) {
    Write-Host "`nFailed files:" -ForegroundColor Red
    foreach ($f in $failedFiles) {
        Write-Host "  - $f" -ForegroundColor Red
    }
    Write-Host "`nIf you see keeper connection errors:" -ForegroundColor Yellow
    Write-Host "  1. Wait 2-3 more minutes" -ForegroundColor Gray
    Write-Host "  2. Run this script again" -ForegroundColor Gray
    Write-Host "  3. Check: docker-compose logs clickhouse-keeper" -ForegroundColor Gray
} else {
    Write-Host "`n[SUCCESS] All tables created!" -ForegroundColor Green
}

# Verify tables
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Verifying tables..." -ForegroundColor Cyan
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"
Write-Host "============================================================" -ForegroundColor Cyan
