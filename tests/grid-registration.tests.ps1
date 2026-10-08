$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
function Assert-Grid([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-GridThrows([scriptblock] $Action, [string] $Pattern) {
    try { & $Action }
    catch {
        Assert-Grid ($_.Exception.Message -match $Pattern) "Unexpected error: $_"
        return
    }
    throw "Expected error matching '$Pattern'."
}

$values = @{
    AZURE_ENV_NAME = 'grid-test'; AZURE_SUBSCRIPTION_ID = 'test-subscription'
    AZURE_RESOURCE_GROUP = 'test-group'; APIC_SERVICE = 'test-center'
    APIC_RESOURCE_ID = '/subscriptions/test-subscription/resourceGroups/test-group/providers/Microsoft.ApiCenter/services/test-center'
    APIC_PRINCIPAL_ID = 'test-principal'; APIC_LOCATION = 'centralus'
    APIM_SERVICE = 'test-apim'; APIM_RESOURCE_ID = '/test/apim'; APIM_GATEWAY_URL = 'https://gateway.example'
    GRID_API_APP_NAME = 'test-api'; GRID_API_APP_URL = 'https://api.example/'
    GRID_MCP_APP_NAME = 'test-mcp'; GRID_MCP_APP_URL = 'https://mcp.example/'
}
$state = @{
    calls = @(); paths = @(); store = @{}; failAt = 0; corrupt = ''
    sku = 'Standard'; images = '["registry.example/grid:deployed"]'
    httpCalls = 0; transientFailures = 0; httpStatus = 0; sleeps = 0
    content = '{"openapi":"3.1.1","info":{"title":"Grid","version":"1.0"},"paths":{}}'
}
function azd {
    $global:LASTEXITCODE = 0
    if (($args[0..1] -join ' ') -eq 'env get-values') { return $values | ConvertTo-Json }
    if (($args[0..1] -join ' ') -eq 'env list') { return '[{"Name":"grid-test","IsDefault":true}]' }
    throw "Unexpected azd command: $args"
}
function az {
    $global:LASTEXITCODE = 0
    if (($args[0..1] -join ' ') -eq 'account show') { return $values.AZURE_SUBSCRIPTION_ID }
    $payloads = @{}
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i].StartsWith('@')) {
            $path = $args[$i].Substring(1)
            $state.paths += $path
            $payloads[$args[$i - 1]] = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        }
    }
    $state.calls += @{ arguments = $args; payloads = $payloads }
    if ($state.calls.Count -eq $state.failAt) {
        $global:LASTEXITCODE = 42
        return 'ERROR: injected CLI failure'
    }
    switch ($args[0]) {
        'containerapp' { return $state.images }
        'resource' { return $state.sku }
        'apic' {
            Assert-Grid ($args[1] -eq 'api' -and $args[2] -in @('create', 'version', 'definition')) 'Unsupported API Center command.'
            return
        }
        'rest' {
            $method = $args[[array]::IndexOf($args, '--method') + 1]
            $url = $args[[array]::IndexOf($args, '--url') + 1]
            Assert-Grid ($url.StartsWith("https://management.azure.com$($values.APIC_RESOURCE_ID)/workspaces/default/") -and
                $url.EndsWith('?api-version=2024-06-01-preview')) 'Wrong catalog scope or API version.'
            Assert-Grid ($method -in @('PUT', 'GET')) 'Registration must never delete assets.'
            if ($method -eq 'PUT') {
                Assert-Grid ($payloads.ContainsKey('--body')) 'ARM JSON must pass through a temporary file.'
                $state.store[$url] = $payloads['--body']
            }
            $item = $state.store[$url] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
            if ($method -eq 'GET' -and $url -match '/deployments/' -and $state.corrupt) {
                switch ($state.corrupt) {
                    'url' { $item.properties.server.runtimeUri = @('https://wrong.example/mcp') }
                    'definition' { $item.properties.definitionId = '/wrong-definition' }
                    'environment' { $item.properties.environmentId = '/wrong-environment' }
                    'source' { $item.properties.apiSourceId = '/synchronized' }
                }
            }
            if ($method -eq 'GET' -and $url -match '/apis/grid-tools-mcp\?' -and $state.corrupt -eq 'kind') {
                $item.properties.kind = 'rest'
            }
            return $item | ConvertTo-Json -Depth 20
        }
        default { throw "Unexpected Azure CLI command: $args" }
    }
}
function Invoke-WebRequest {
    param($Uri, $TimeoutSec, $MaximumRedirection)
    Assert-Grid ($Uri -eq 'https://api.example/openapi/v1.json' -and $TimeoutSec -eq 30) 'Wrong OpenAPI URL or timeout.'
    $state.httpCalls++
    if ($state.httpCalls -le $state.transientFailures) {
        if ($state.httpStatus) {
            $response = [System.Net.Http.HttpResponseMessage]::new($state.httpStatus)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('HTTP failure', $response)
        }
        throw [System.TimeoutException]::new('Timed out')
    }
    return @{ StatusCode = 200; Content = $state.content }
}
function Start-Sleep {
    param($Seconds)
    Assert-Grid ($Seconds -eq 5) 'Unexpected retry delay.'
    $state.sleeps++
}
function Invoke-GridScript([string] $Name) {
    $state.calls = @(); $state.paths = @(); $state.httpCalls = 0; $state.sleeps = 0
    try { & (Join-Path $root "scripts\$Name") | Out-Null }
    finally {
        foreach ($path in $state.paths) { Assert-Grid (-not (Test-Path -LiteralPath $path)) 'Registration leaked temporary JSON.' }
    }
}

$saved = @{}
foreach ($key in @($values.Keys) + @('RESOURCE_GROUP', 'APIM_RESOURCE_GROUP', 'LOCATION', 'API_ID', 'API_TITLE', 'ENV_DEV', 'ENV_TEST', 'ENV_PROD')) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    $apiScript = '10-register-grid-telemetry-api.ps1'
    $mcpScript = '11-register-mcp-server.ps1'
    Invoke-GridScript $apiScript
    Assert-Grid ($state.calls.Count -eq 5) 'Wrong REST registration command count.'
    Assert-Grid ($state.calls[-1].payloads['--specification'].version -eq '3.1.1') 'Live OpenAPI version was replaced with a hard-coded version.'
    Assert-Grid (($state.calls[1].payloads['--custom-properties'].complianceTag -join ',') -eq 'NERC-CIP') 'REST compliance tags must match script 02.'
    Invoke-GridScript $mcpScript
    Assert-Grid ($state.calls.Count -eq 9 -and $state.store.Count -eq 5) 'MCP registration must create five catalog records and read back API/deployment.'
    $apiKey = "https://management.azure.com$($values.APIC_RESOURCE_ID)/workspaces/default/apis/grid-tools-mcp?api-version=2024-06-01-preview"
    Assert-Grid ($state.store[$apiKey].properties.kind -eq 'mcp' -and
        ($state.store[$apiKey].properties.customProperties.complianceTag -join ',') -eq 'NERC-CIP') 'MCP kind or metadata is incorrect.'
    Invoke-GridScript $mcpScript
    Assert-Grid ($state.store.Count -eq 5) 'Reruns must reuse stable catalog IDs.'
    foreach ($corruption in @('url', 'kind', 'definition', 'environment', 'source')) {
        $state.corrupt = $corruption
        Assert-GridThrows { Invoke-GridScript $mcpScript } 'Catalog readback failed'
    }
    $state.corrupt = ''
    foreach ($script in @($apiScript, $mcpScript)) {
        $count = if ($script -eq $apiScript) { 5 } else { 9 }
        for ($i = 1; $i -le $count; $i++) {
            $state.failAt = $i
            Assert-GridThrows { Invoke-GridScript $script } 'Azure CLI exit code 42'
            Assert-Grid ($state.calls.Count -eq $i) 'Registration continued after CLI failure.'
        }
        $state.failAt = 0
        $state.images = '["mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"]'
        Assert-GridThrows { Invoke-GridScript $script } 'provisioning placeholder.*azd deploy'
        Assert-Grid ($state.httpCalls -eq 0 -and @($state.calls | Where-Object { $_.arguments[0] -in @('apic', 'rest') }).Count -eq 0) 'Placeholder must fail before HTTP or catalog writes.'
        $state.images = '["registry.example/grid:deployed"]'
    }
    $state.images = '[]'
    Assert-GridThrows { Invoke-GridScript $apiScript } 'did not return any container images'
    $state.images = '["registry.example/grid:deployed"]'
    $state.sku = 'Free'
    Assert-GridThrows { Invoke-GridScript $mcpScript } 'must be on the Standard plan'
    Assert-Grid ($state.calls.Count -eq 1) 'Free plan must stop before catalog writes.'
    $state.sku = 'Standard'
    foreach ($status in @(0, 429, 503)) {
        $state.httpStatus = $status
        $state.transientFailures = 2
        Invoke-GridScript $apiScript
        Assert-Grid ($state.httpCalls -eq 3 -and $state.sleeps -eq 2) 'Transient HTTP failures must be retried.'
    }
    $state.transientFailures = 3
    Assert-GridThrows { Invoke-GridScript $apiScript } 'Failed to download.*Container App'
    Assert-Grid ($state.calls.Count -eq 1 -and $state.httpCalls -eq 3 -and $state.sleeps -eq 2) 'Exhausted retries must stop before catalog writes.'
    $state.httpStatus = 404
    Assert-GridThrows { Invoke-GridScript $apiScript } 'Failed to download'
    Assert-Grid ($state.httpCalls -eq 1 -and $state.sleeps -eq 0) 'Permanent HTTP failures must not be retried.'
    $state.transientFailures = 0
    foreach ($content in @('<html>placeholder</html>', '{}', 'null', '[]', '{"openapi":""}', '')) {
        $state.content = $content
        Assert-GridThrows { Invoke-GridScript $apiScript } 'OpenAPI'
        Assert-Grid ($state.calls.Count -eq 1) 'Invalid OpenAPI must not reach the catalog.'
    }
    Write-Host 'Grid registration checks passed.'
}
finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
