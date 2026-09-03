# 01-create-service.ps1 — create the resource group and the API Center service.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

Write-Host "==> Ensuring Azure API Center CLI extension is installed"
az extension add --name apic-extension --upgrade --yes
if ($LASTEXITCODE -ne 0) { throw "Failed to install or upgrade apic-extension." }

Write-Host "==> Creating resource group $($env:RESOURCE_GROUP) in $($env:LOCATION)"
az group create --name $env:RESOURCE_GROUP --location $env:LOCATION -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group '$($env:RESOURCE_GROUP)'." }

Write-Host "==> Creating API Center service $($env:APIC_SERVICE)"
az apic create `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:APIC_SERVICE `
  --location $env:LOCATION `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create API Center service '$($env:APIC_SERVICE)'." }

Write-Host "==> Done. This is your single system of record — currently empty."
