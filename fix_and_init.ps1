# Complete fix and initialization script
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "ClickHouse Complete Fix and Initialization" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`n[1/5] Stopping all containers..." -ForegroundColor Yellow
docker-compose down -v
Start-Sleep -Seconds 2

Write-Host "`n[2/5] Starting containers..." -ForegroundColor Yellow
docker-compose up -d

Write-Host "`n[3/5] Waiting for containers to be healthy..." -ForegroundColor Yellow
$maxWait = 60
$waited = 0
while ($waited -lt $maxWait) {
    $healthy = docker ps --filter "name=clickhouse" --filter "health=healthy" --format "{{.Names}}" | Measure-Object | Select-Object -ExpandProperty Count
    if ($healthy -eq 3) {
        Write-Host "  [OK] All containers are healthy!" -ForegroundColor Green
        break
    }
    Write-Host "  Waiting... ($healthy/3 healthy, $waited/$maxWait seconds)" -ForegroundColor Gray
    Start-Sleep -Seconds 5
    $waited += 5
}

Write-Host "`n[4/5] Testing ClickHouse Server connectivity..." -ForegroundColor Yellow
$retries = 0
$maxRetries = 12
$connected = $false
while ($retries -lt $maxRetries) {
    try {
        $result = docker exec clickhouse-01 clickhouse-client --query "SELECT 1" 2>&1
        if ($result -eq "1") {
            Write-Host "  [OK] ClickHouse Server is responding!" -ForegroundColor Green
            $connected = $true
            break
        }
    } catch {
        # Retry
    }
    $retries++
    Write-Host "  Retry $retries/$maxRetries..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
}

if (-not $connected) {
    Write-Host "  [ERROR] Could not connect to ClickHouse Server" -ForegroundColor Red
    exit 1
}

Write-Host "`n[5/5] Initializing schema..." -ForegroundColor Yellow

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
        Write-Host "`n  Executing $file..." -ForegroundColor Cyan
        $content = Get-Content $file -Raw
        
        # Execute and capture output
        $output = $content | docker exec -i clickhouse-01 clickhouse-client --multiquery 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [✓] Success" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "    [✗] Failed" -ForegroundColor Red
            $failedFiles += $file
            Write-Host "    Error: $output" -ForegroundColor Red
        }
    }
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Results" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Successfully executed: $successCount/$($sqlFiles.Count)" -ForegroundColor $(if ($successCount -eq $sqlFiles.Count) { "Green" } else { "Yellow" })

if ($failedFiles.Count -gt 0) {
    Write-Host "`nFailed files:" -ForegroundColor Red
    foreach ($f in $failedFiles) {
        Write-Host "  - $f" -ForegroundColor Red
    }
} else {
    Write-Host "`n[SUCCESS] All tables created!" -ForegroundColor Green
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Verifying tables..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"
