# Requires: Run as Administrator

$startTime = Get-Date
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath
$logFile = Join-Path $scriptDir "network_block_log.txt"

$wifiName = "Wi-Fi"
$checkInterval = 10  # seconds
$statusPrintInterval = 10  # minutes

$lastPrint = $startTime
$loggedProcesses = @{}

$logHeader = "====== NETWORK BLOCK SESSION ======`nStart: $startTime`nLog File: $logFile`n==================================="
$logHeader | Out-File -FilePath $logFile -Encoding UTF8 -Append
Clear-Host

Write-Host "`n==================== ENFORCE NETWORK BLOCK ====================" -ForegroundColor Cyan
Write-Host "Start Time: $startTime"
Write-Host "Enforcing Wi-Fi and Bluetooth block... (Press Ctrl+C to stop)" -ForegroundColor Yellow
Write-Host "Log file: $logFile"
Write-Host "Tracking user applications only..." -ForegroundColor Green
Write-Host "=================================================================`n"

function Disable-WiFi {
    $adapter = Get-NetAdapter -Name $wifiName -ErrorAction SilentlyContinue
    if ($adapter -and $adapter.Status -ne "Disabled") {
        Disable-NetAdapter -Name $wifiName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Disable-Bluetooth {
    $btDevices = Get-PnpDevice | Where-Object { $_.FriendlyName -match "Bluetooth" -and $_.Status -eq "OK" }
    foreach ($dev in $btDevices) {
        Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Log-Status {
    $now = Get-Date
    $elapsed = [math]::Round(($now - $startTime).TotalMinutes, 1)
    $wifiStatus = (Get-NetAdapter -Name $wifiName -ErrorAction SilentlyContinue).Status
    $btStatusList = (Get-PnpDevice | Where-Object { $_.FriendlyName -match "Bluetooth" }).Status
    $btStatus = if ($btStatusList) { ($btStatusList | Select-Object -First 1) } else { "Not Found" }

    $status = "[$now] Running for $elapsed min | Wi-Fi: $wifiStatus | Bluetooth: $btStatus"
    Write-Host "`n$status"
    $status | Out-File -FilePath $logFile -Append
}

# Log stop time if script is closed
Register-EngineEvent PowerShell.Exiting -Action {
    $stopTime = Get-Date
    "`nStopped at: $stopTime`n===================================`n" | Out-File -FilePath $logFile -Append
}

# Main loop
while ($true) {
    # Enforce Wi-Fi and Bluetooth off
    Disable-WiFi
    Disable-Bluetooth

    # Log status every 10 minutes
    $now = Get-Date
    if (($now - $lastPrint).TotalMinutes -ge $statusPrintInterval) {
        Log-Status
        $lastPrint = $now
    }

    # Track newly started user-facing applications
    $processes = Get-Process | Where-Object {
        $_.MainWindowTitle -ne "" -or
        ($_.Path -ne $null -and $_.Path -notlike "C:\Windows\*")
    } | Select-Object Id, ProcessName

    foreach ($proc in $processes) {
        $key = "$($proc.Id)-$($proc.ProcessName)"
        if (-not $loggedProcesses.ContainsKey($key)) {
            $loggedProcesses[$key] = $true
            $logLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Application Started: $($proc.ProcessName) (PID: $($proc.Id))"
            Write-Host $logLine -ForegroundColor Magenta
            $logLine | Out-File -FilePath $logFile -Append
        }
    }

    Start-Sleep -Seconds $checkInterval
}
