# 99-cleanup.ps1 — tear down everything created for the demo.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

$Confirm = Read-Host "This will delete resource group '$($env:RESOURCE_GROUP)' and ALL resources in it. Continue? [y/N]"
if ($Confirm -ne "y" -and $Confirm -ne "Y") {
    Write-Host "Aborted."
    exit 0
}

az group delete --name $env:RESOURCE_GROUP --yes --no-wait
Write-Host "==> Deletion of $($env:RESOURCE_GROUP) started (running in background)."
