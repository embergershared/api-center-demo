# 10-register-grid-telemetry-api.ps1 — register the deployed Grid Telemetry API
# in API Center from the live OpenAPI document exposed by the Container App.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-vars.ps1')
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

$apiId = 'grid-telemetry-api'
$versionId = 'v1-0'
$definitionId = 'openapi'
$gridApiAppUrl = Get-DeploymentValue $deploymentValues 'GRID_API_APP_URL'
$gridApiAppName = Get-DeploymentValue $deploymentValues 'GRID_API_APP_NAME'
$openApiUrl = "$($gridApiAppUrl.TrimEnd('/'))/openapi/v1.json"

Assert-DemoContainerAppDeployed -AppName $gridApiAppName -ServiceName 'grid-telemetry-api'
Write-Host "==> Downloading the live OpenAPI document from $openApiUrl"
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $response = Invoke-WebRequest -Uri $openApiUrl -TimeoutSec 30 -MaximumRedirection 5
        break
    }
    catch {
        $statusCode = if ($null -ne $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($attempt -eq 3 -or ($statusCode -ne 0 -and $statusCode -notin @(408, 429, 500, 502, 503, 504))) {
            throw "Failed to download the live OpenAPI document from '$openApiUrl'. Check Container App '$gridApiAppName' with 'az containerapp logs show --name $gridApiAppName --resource-group $env:RESOURCE_GROUP --type system'. Deploy the application with 'azd deploy grid-telemetry-api' if needed. $($_.Exception.Message)"
        }
        Write-Warning "OpenAPI request failed (attempt $attempt/3); retrying in 5 seconds. $($_.Exception.Message)"
        Start-Sleep -Seconds 5
    }
}

if ($response.StatusCode -ne 200 -or [string]::IsNullOrWhiteSpace($response.Content)) {
    throw "Container App '$gridApiAppName' returned HTTP $($response.StatusCode) without a usable OpenAPI payload at '$openApiUrl'. Ensure the deployment is healthy before retrying."
}

try {
    $specificationDocument = $response.Content | ConvertFrom-Json -AsHashtable
}
catch {
    throw "The response from '$openApiUrl' was not valid OpenAPI JSON. $($_.Exception.Message)"
}

if ($specificationDocument -isnot [System.Collections.IDictionary] -or
    -not ($specificationDocument.ContainsKey('openapi') -or $specificationDocument.ContainsKey('swagger'))) {
    throw "The response from '$openApiUrl' did not contain an OpenAPI version field."
}
$specificationVersion = if ($specificationDocument.ContainsKey('openapi')) { $specificationDocument.openapi } else { $specificationDocument.swagger }
if ([string]::IsNullOrWhiteSpace($specificationVersion)) {
    throw "The response from '$openApiUrl' contained an empty OpenAPI version."
}

$customProperties = '{
    "lifecycleStage": "production",
    "businessOwner": "Grid Operations Team <grid-ops@contoso.com>",
    "complianceTag": ["NERC-CIP"]
  }'

$temporarySpecificationPath = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -LiteralPath $temporarySpecificationPath -Value $response.Content -Encoding utf8

    Write-Host "==> Creating the API entity in the catalog for $gridApiAppName"
    Invoke-DemoAz -Arguments @(
        'apic', 'api', 'create',
        '--resource-group', $env:RESOURCE_GROUP,
        '--service-name', $env:APIC_SERVICE,
        '--api-id', $apiId,
        '--title', 'Grid Telemetry API',
        '--type', 'rest',
        '--summary', 'Synthetic production grid telemetry for the Grid Maintenance Agent demo.',
        '--description', "Live Container App-backed grid telemetry API hosted by '$gridApiAppName'.",
        '-o', 'table'
    ) -JsonArguments @{ '--custom-properties' = $customProperties } `
        -FailureMessage "Failed to create API '$apiId'"

    Write-Host '==> Creating version v1'
    Invoke-DemoAz -Arguments @(
        'apic', 'api', 'version', 'create',
        '--resource-group', $env:RESOURCE_GROUP,
        '--service-name', $env:APIC_SERVICE,
        '--api-id', $apiId,
        '--version-id', $versionId,
        '--title', 'v1',
        '--lifecycle-stage', 'production',
        '-o', 'table'
    ) -FailureMessage "Failed to create API version '$versionId'"

    Write-Host '==> Creating the OpenAPI definition and importing the live specification'
    Invoke-DemoAz -Arguments @(
        'apic', 'api', 'definition', 'create',
        '--resource-group', $env:RESOURCE_GROUP,
        '--service-name', $env:APIC_SERVICE,
        '--api-id', $apiId,
        '--version-id', $versionId,
        '--definition-id', $definitionId,
        '--title', "OpenAPI $specificationVersion",
        '--description', 'Live OpenAPI document imported from the deployed GridTelemetry.Api endpoint.',
        '-o', 'table'
    ) -FailureMessage "Failed to create API definition '$definitionId'"

    Invoke-DemoAz -Arguments @(
        'apic', 'api', 'definition', 'import-specification',
        '--resource-group', $env:RESOURCE_GROUP,
        '--service-name', $env:APIC_SERVICE,
        '--api-id', $apiId,
        '--version-id', $versionId,
        '--definition-id', $definitionId,
        '--format', 'inline',
        '--value', "@$temporarySpecificationPath",
        '-o', 'table'
    ) -JsonArguments @{ '--specification' = (@{ name = 'openapi'; version = $specificationVersion } | ConvertTo-Json -Compress) } `
        -FailureMessage "Failed to import the live OpenAPI specification for '$apiId'"
}
finally {
    Remove-Item -LiteralPath $temporarySpecificationPath -Force -ErrorAction SilentlyContinue
}

Write-Host "==> Registered. In the portal, search for 'grid telemetry' to show the live Grid Telemetry API entry."
