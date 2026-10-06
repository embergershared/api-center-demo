# 01-create-service.ps1 — create the resource group(s), the API Center service
# (Standard plan), and the APIM instance (Consumption tier) used by 05-link-apim.ps1.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

Write-Host "==> Ensuring Azure API Center CLI extension is installed"
az extension add --name apic-extension --upgrade --yes
if ($LASTEXITCODE -ne 0) { throw "Failed to install or upgrade apic-extension." }

foreach ($ResourceGroup in @($env:RESOURCE_GROUP, $env:APIM_RESOURCE_GROUP) | Where-Object { $_ } | Select-Object -Unique) {
    Write-Host "==> Creating resource group $ResourceGroup in $($env:LOCATION)"
    az group create --name $ResourceGroup --location $env:LOCATION -o table
    if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group '$ResourceGroup'." }
}

Write-Host "==> Creating API Center service $($env:APIC_SERVICE)"
az apic create `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:APIC_SERVICE `
  --location $env:LOCATION `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create API Center service '$($env:APIC_SERVICE)'." }

# 'az apic create' has no --sku option (it creates a Free plan service), so set the plan via ARM.
Write-Host "==> Setting API Center $($env:APIC_SERVICE) to the Standard plan"
$ApicId = az apic show --resource-group $env:RESOURCE_GROUP --name $env:APIC_SERVICE --query id -o tsv
if ($LASTEXITCODE -ne 0) { throw "Failed to get API Center service '$($env:APIC_SERVICE)'." }
$SkuFile = Join-Path ([System.IO.Path]::GetTempPath()) "apic-sku.json"
[System.IO.File]::WriteAllText($SkuFile, '{"sku":{"name":"Standard"}}')
az rest --method patch --url "${ApicId}?api-version=2024-03-01" --body "@$SkuFile" -o none
$SkuExitCode = $LASTEXITCODE
Remove-Item $SkuFile -ErrorAction SilentlyContinue
if ($SkuExitCode -ne 0) { throw "Failed to set the Standard plan on '$($env:APIC_SERVICE)'." }
$Sku = az apic show --resource-group $env:RESOURCE_GROUP --name $env:APIC_SERVICE --query sku.name -o tsv
if ($Sku -ne "Standard") { throw "API Center '$($env:APIC_SERVICE)' plan is '$Sku', expected 'Standard'." }
Write-Host "    Plan: $Sku"

if ([string]::IsNullOrEmpty($env:APIM_SERVICE)) {
    Write-Host "==> APIM_SERVICE is not set in 00-vars.ps1 — skipping APIM creation."
} else {
    $ApimNames = az apim list --resource-group $env:APIM_RESOURCE_GROUP --query "[].name" -o tsv
    if ($LASTEXITCODE -ne 0) { throw "Failed to list APIM instances in '$($env:APIM_RESOURCE_GROUP)'." }
    if (@($ApimNames) -contains $env:APIM_SERVICE) {
        Write-Host "==> APIM instance $($env:APIM_SERVICE) already exists — skipping creation."
    } else {
        Write-Host "==> Creating APIM instance $($env:APIM_SERVICE) (Consumption tier)"
        az apim create `
          --resource-group $env:APIM_RESOURCE_GROUP `
          --name $env:APIM_SERVICE `
          --location $env:LOCATION `
          --sku-name Consumption `
          --publisher-email "you@contoso.com" `
          --publisher-name "Contoso" `
          -o table
        if ($LASTEXITCODE -ne 0) { throw "Failed to create APIM instance '$($env:APIM_SERVICE)'." }
    }
}

Write-Host "==> Done. This is your single system of record — currently empty."
