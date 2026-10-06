# 99-cleanup.ps1 — tear down everything created for the demo.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

$Confirm = Read-Host "This will delete resource group '$($env:RESOURCE_GROUP)' and ALL resources in it. Continue? [y/N]"
if ($Confirm -ne "y" -and $Confirm -ne "Y") {
    Write-Host "Aborted."
    exit 0
}

az group delete --name $env:RESOURCE_GROUP --yes --no-wait
if ($LASTEXITCODE -ne 0) { throw "Failed to start deletion of resource group '$($env:RESOURCE_GROUP)'." }

# Poll every 10s, updating a single console line, until the group is gone or deletion stops.
$PollSeconds = 10
$TimeoutSeconds = 3600
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
while ($true) {
    $State = az group show --name $env:RESOURCE_GROUP --query properties.provisioningState -o tsv 2>$null
    if ($LASTEXITCODE -ne 0) {
        $Status = if ((az group exists --name $env:RESOURCE_GROUP) -eq 'false') { 'Succeeded' } else { 'Unknown' }
        break
    }
    if ($State -ne 'Deleting') { $Status = 'Failed'; break }
    if ($Stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $Status = 'TimedOut'; break }
    Write-Host -NoNewline "`rDeleting Resource Group: $($env:RESOURCE_GROUP) for $([int]$Stopwatch.Elapsed.TotalSeconds) seconds."
    Start-Sleep -Seconds $PollSeconds
}
$Elapsed = [int]$Stopwatch.Elapsed.TotalSeconds
Write-Host ""

switch ($Status) {
    'Succeeded' { Write-Host "==> SUCCESS: resource group '$($env:RESOURCE_GROUP)' deleted in $Elapsed seconds." -ForegroundColor Green }
    'Failed'    { Write-Host "==> FAILED: deletion of '$($env:RESOURCE_GROUP)' stopped after $Elapsed seconds (provisioning state: $State). Check the activity log." -ForegroundColor Red; exit 1 }
    'TimedOut'  { Write-Host "==> TIMED OUT: '$($env:RESOURCE_GROUP)' still deleting after $Elapsed seconds; stopped polling. Check the portal." -ForegroundColor Yellow; exit 1 }
    default     { Write-Host "==> UNKNOWN: could not determine the status of '$($env:RESOURCE_GROUP)' after $Elapsed seconds." -ForegroundColor Yellow; exit 1 }
}
