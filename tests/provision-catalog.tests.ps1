$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\provision-catalog.ps1')

function Assert-Catalog([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-DeploymentSubscription { param($SubscriptionId) }
$values = @{
    AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000001'
    AZURE_RESOURCE_GROUP = 'test-group'
    APIC_SERVICE = 'test-center'
    APIC_RESOURCE_ID = '/subscriptions/test/resourceGroups/test/providers/Microsoft.ApiCenter/services/test'
    APIM_RESOURCE_ID = '/subscriptions/test/resourceGroups/test/providers/Microsoft.ApiManagement/service/test'
    APIM_GATEWAY_URL = 'https://test.azure-api.net'
    MSLEARN_MCP_URL = 'https://test.azure-api.net/learn-mcp/mcp'
    AZURE_DEPLOYMENT_PROFILE = 'full'
}
$store = @{}
$imports = [System.Collections.Generic.List[string]]::new()
$corruptReadback = $false
$failImport = $false
function Invoke-DemoAz {
    param($Arguments, $JsonArguments = @{}, $FailureMessage)
    if (($Arguments[0..3] -join ' ') -eq 'apic api definition import-specification') {
        if ($failImport) { throw 'Import failed' }
        $id = $Arguments[[array]::IndexOf($Arguments, '--api-id') + 1]
        Assert-Catalog ($Arguments[[array]::IndexOf($Arguments, '--version-id') + 1] -eq 'v1-0-0') 'Imported version must use an API Center CLI-compatible ID.'
        $file = $Arguments[[array]::IndexOf($Arguments, '--value') + 1]
        Assert-Catalog (Test-Path $file.Substring(1)) 'Specification file missing.'
        $imports.Add($id)
        return
    }
    Assert-Catalog ($Arguments[0] -eq 'rest') "Unexpected CLI command: $Arguments"
    $method = $Arguments[[array]::IndexOf($Arguments, '--method') + 1]
    $url = $Arguments[[array]::IndexOf($Arguments, '--url') + 1]
    Assert-Catalog ($method -in @('GET','PUT')) 'Provisioning must never delete catalog entries.'
    if ($method -eq 'PUT') {
        $store[$url] = $JsonArguments['--body'] | ConvertFrom-Json -AsHashtable
        return $JsonArguments['--body']
    }
    $item = $store[$url] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    if ($corruptReadback -and $url -match '/deployments/') { $item.properties.server.runtimeUri = @('https://wrong.example/mcp') }
    return $item | ConvertTo-Json -Depth 20
}
Set-ProvisionedCatalog $values
Assert-Catalog ($imports.Count -eq 2) 'Full profile must import two REST specs.'
Assert-Catalog (-not @($store.Keys | Where-Object { $_ -match '/apiSources/|/environments/azure-api-management' }).Count) 'Provisioning must not create APIM integration resources.'
$apis = @($store.Keys | Where-Object { $_ -match '/apis/managed-[^/]+\?' })
Assert-Catalog ($apis.Count -eq 3) 'Full profile must provision three independent entries.'
foreach ($key in $apis) {
    Assert-Catalog (-not $store[$key].properties.ContainsKey('apiSourceId')) 'Managed APIs must not attach to synchronization.'
    Assert-Catalog ($store[$key].properties.customProperties.businessOwner -and
        $store[$key].properties.customProperties.lifecycleStage) 'Required metadata missing.'
}
Set-ProvisionedCatalog $values
Assert-Catalog (@($store.Keys | Where-Object { $_ -match '/apis/managed-[^/]+\?' }).Count -eq 3) 'Reruns must reuse independent entries.'
$corruptReadback = $true
try { Set-ProvisionedCatalog $values; throw 'Expected readback failure.' }
catch { Assert-Catalog ($_.Exception.Message -match 'readback failed') 'Stale runtime URL must be detected.' }
$corruptReadback = $false
$failImport = $true
try { Set-ProvisionedCatalog $values; throw 'Expected import failure.' }
catch { Assert-Catalog ($_.Exception.Message -eq 'Import failed') 'Import failure must propagate.' }
$failImport = $false
$store.Clear()
$imports.Clear()
$values.AZURE_DEPLOYMENT_PROFILE = 'core'
Set-ProvisionedCatalog $values
Assert-Catalog (@($store.Keys | Where-Object { $_ -match '/apis/managed-[^/]+\?' }).Count -eq 2 -and
    $imports.Count -eq 1 -and $imports[0] -eq 'managed-fleet-vehicle') 'Core must not advertise an unprovisioned AI gateway.'
Write-Host 'Catalog provisioning checks passed.'
