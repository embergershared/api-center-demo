# 00-vars.ps1 — shared variables for the API Center demo.
# Dot-source this at the top of every script: `. ./00-vars.ps1`

# ---- EDIT THESE ----
$env:RESOURCE_GROUP      = "rg-apic-demo-eus01"
$env:LOCATION            = "eastus"
$env:APIM_SERVICE        = ""                           # existing APIM name, optional (step 05)
$env:APIM_RESOURCE_GROUP = $env:RESOURCE_GROUP           # RG of the existing APIM, if different

$statePath = Join-Path $PSScriptRoot "../.apic-demo-state.json"
$requestedService = $env:APIC_SERVICE
$savedState = if (Test-Path $statePath) {
	Get-Content $statePath -Raw | ConvertFrom-Json
}

$existingJson = az resource list `
  --resource-group $env:RESOURCE_GROUP `
  --resource-type "Microsoft.ApiCenter/services" `
  --query "[].name" `
  -o json 2>$null
[string[]]$existingServices = if ($LASTEXITCODE -eq 0 -and $existingJson) {
	@($existingJson | ConvertFrom-Json)
} else {
	@()
}

if ($existingServices.Count -eq 1) {
	$env:APIC_SERVICE = $existingServices[0]
} elseif ($existingServices.Count -gt 1) {
	$preferredService = @($requestedService, $savedState.apiCenterService) |
		Where-Object { $_ -and $_ -in $existingServices } |
		Select-Object -First 1
	if (-not $preferredService) {
		throw "Multiple API Center services exist in '$($env:RESOURCE_GROUP)'. Set APIC_SERVICE to the intended existing service before running this script."
	}
	$env:APIC_SERVICE = $preferredService
} elseif (-not [string]::IsNullOrWhiteSpace($requestedService)) {
	$env:APIC_SERVICE = $requestedService
} elseif ($savedState -and $savedState.resourceGroup -eq $env:RESOURCE_GROUP) {
	$env:APIC_SERVICE = $savedState.apiCenterService
} else {
	$env:APIC_SERVICE = "apic-demo-$(Get-Random)"
}

@{
	resourceGroup = $env:RESOURCE_GROUP
	apiCenterService = $env:APIC_SERVICE
} | ConvertTo-Json | Set-Content $statePath

# Logical names used across scripts
$env:API_ID    = "fleet-vehicle-api"
$env:API_TITLE = "Fleet Vehicle API"
$env:ENV_DEV   = "dev"
$env:ENV_TEST  = "test"
$env:ENV_PROD  = "prod"

Write-Host "Vars loaded: RG=$($env:RESOURCE_GROUP) LOCATION=$($env:LOCATION) APIC_SERVICE=$($env:APIC_SERVICE)"
