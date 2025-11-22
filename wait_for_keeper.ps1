# Script to wait for ClickHouse Keeper to be ready
# Run this before initializing schema

Write-Host "Waiting for ClickHouse Keeper to be ready..." -ForegroundColor Yellow

$maxWait = 180  # 3 minutes
$waited = 0
$keeperReady = $false

while ($waited -lt $maxWait) {
    try {
        # Test if keeper is accessible
        $result = docker exec clickhouse-keeper clickhouse-keeper-cli --host localhost --port 9181 --command "stat /" 2>&1
        if ($LASTEXITCODE -eq 0 -or $result -match "cZxid") {
            $keeperReady = $true
            Write-Host "`n[SUCCESS] Keeper is ready!" -ForegroundColor Green
            break
        }
    } catch {
        # Continue waiting
    }
    
    Write-Host "." -NoNewline -ForegroundColor Gray
    Start-Sleep -Seconds 5
    $waited += 5
}

if (-not $keeperReady) {
    Write-Host "`n[WARNING] Keeper not ready after $maxWait seconds" -ForegroundColor Yellow
    Write-Host "You can still try initialization - it might work now." -ForegroundColor Yellow
} else {
    Write-Host "Keeper ready after $waited seconds" -ForegroundColor Green
}
