# 00-vars.ps1 — shared variables for the API Center demo.
# Initialize once with parameters; later scripts reuse the environment values.

param(
	[string]$BaseValue = $env:APIC_BASE_VALUE,

	[string]$PublisherEmail = $env:APIM_PUBLISHER_EMAIL,

	[string]$PublisherName = $env:APIM_PUBLISHER_NAME
)

if ($BaseValue -notmatch '^[A-Za-z0-9]{3,4}$') {
	throw "BaseValue must be a 3-4 character alphanumeric value, such as your initials."
}
if ($PublisherEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
	throw "PublisherEmail must be a valid email address."
}
if ([string]::IsNullOrWhiteSpace($PublisherName)) {
	throw "PublisherName must be an organization name."
}

$normalizedBaseValue = $BaseValue.ToLowerInvariant()
$env:APIC_BASE_VALUE      = $normalizedBaseValue
$env:RESOURCE_GROUP      = "rg-apic-demo-eus01"
$env:LOCATION            = "eastus"
$env:APIC_SERVICE        = "apic-$normalizedBaseValue-eus02"
$env:APIM_RESOURCE_GROUP = $env:RESOURCE_GROUP
$env:APIM_SERVICE        = "apim-$normalizedBaseValue-eus02"
$env:APIM_PUBLISHER_EMAIL = $PublisherEmail
$env:APIM_PUBLISHER_NAME  = $PublisherName

# Logical names used across scripts
$env:API_ID    = "fleet-vehicle-api"
$env:API_TITLE = "Fleet Vehicle API"
$env:ENV_DEV   = "dev"
$env:ENV_TEST  = "test"
$env:ENV_PROD  = "prod"

Write-Host ""
Write-Host "API Center demo variables:"
Write-Host "APIC_BASE_VALUE=$($env:APIC_BASE_VALUE)"
Write-Host "RESOURCE_GROUP=$($env:RESOURCE_GROUP)"
Write-Host "LOCATION=$($env:LOCATION)"
Write-Host "APIC_SERVICE=$($env:APIC_SERVICE)"
Write-Host "APIM_RESOURCE_GROUP=$($env:APIM_RESOURCE_GROUP)"
Write-Host "APIM_SERVICE=$($env:APIM_SERVICE)"
Write-Host "APIM_PUBLISHER_EMAIL=$($env:APIM_PUBLISHER_EMAIL)"
Write-Host "APIM_PUBLISHER_NAME=$($env:APIM_PUBLISHER_NAME)"
Write-Host "API_ID=$($env:API_ID)"
Write-Host "API_TITLE=$($env:API_TITLE)"
Write-Host "ENV_DEV=$($env:ENV_DEV)"
Write-Host "ENV_TEST=$($env:ENV_TEST)"
Write-Host "ENV_PROD=$($env:ENV_PROD)"
