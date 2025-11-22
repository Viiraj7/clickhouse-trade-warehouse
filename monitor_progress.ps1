# Monitor tick ingestion progress
$target = 1000000
Write-Host "`n===================================" -ForegroundColor Cyan
Write-Host "  TICK INGESTION MONITOR" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Target: 1,000,000 ticks`n" -ForegroundColor Yellow

while ($true) {
    $count = docker exec clickhouse-01 clickhouse-client -q "SELECT COUNT() FROM default.ticks_all"
    $countNum = [int]$count
    
    if ($countNum -ge $target) {
        Write-Host "`n🎉 TARGET REACHED!" -ForegroundColor Green
        Write-Host "Final count: $($countNum.ToString('N0')) ticks" -ForegroundColor Cyan
        break
    }
    
    $pct = [math]::Round(($countNum / $target) * 100, 1)
    $bar = ""
    $barLength = [math]::Floor($pct / 2)
    for ($i = 0; $i -lt $barLength; $i++) { $bar += "█" }
    for ($i = $barLength; $i -lt 50; $i++) { $bar += "░" }
    
    $remaining = $target - $countNum
    $eta = [math]::Round($remaining / 2000 / 60, 1)
    
    Write-Host "`r[$bar] $pct% | $($countNum.ToString('N0')) / 1,000,000 | ETA: $eta min   " -NoNewline -ForegroundColor Cyan
    
    Start-Sleep -Seconds 5
}

Write-Host "`n`nData generation complete! Ready for benchmarking.`n" -ForegroundColor Green
