[CmdletBinding()]
param(
    [Parameter(Mandatory)][System.Collections.IDictionary] $Values,
    [object[]] $ExistingDeployments = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')

function Invoke-ModelDiscovery {
    param([string[]] $Arguments)
    $result = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "AI preflight failed: az $($Arguments -join ' ')" }
    return ($result -join [Environment]::NewLine) | ConvertFrom-Json -Depth 30
}

function Get-PositiveParameter {
    param([string] $Name)
    $value = Get-DeploymentParameterValue $Values $Name
    $number = 0
    if (-not [int]::TryParse($value, [ref]$number) -or $number -lt 1) {
        throw "Parameter '$Name' must be a positive integer."
    }
    return $number
}

$location = Get-DeploymentParameterValue $Values 'aiLocation'
$subscription = Get-DeploymentValue $Values 'AZURE_SUBSCRIPTION_ID'
$redisSku = Get-DeploymentParameterValue $Values 'redisSku'
if ($redisSku -cnotin @('Balanced_B0', 'Balanced_B1')) { throw 'REDIS_SKU must be Balanced_B0 or Balanced_B1.' }
$ha = Get-DeploymentParameterValue $Values 'redisHighAvailability'
if ($ha -cnotin @('true', 'false')) { throw 'REDIS_HIGH_AVAILABILITY must be true or false.' }
$null = Get-PositiveParameter 'tokensPerMinute'
$null = Get-PositiveParameter 'tokensPerDay'

$models = @(Invoke-ModelDiscovery @('cognitiveservices', 'model', 'list', '--location', $location, '--subscription', $subscription))
$usages = @(Invoke-ModelDiscovery @('cognitiveservices', 'usage', 'list', '--location', $location, '--subscription', $subscription))
$quotaRequested = @{}
foreach ($kind in @('chat', 'embedding')) {
    $name = Get-DeploymentParameterValue $Values "${kind}ModelName"
    $version = Get-DeploymentParameterValue $Values "${kind}ModelVersion"
    $skuName = Get-DeploymentParameterValue $Values "${kind}DeploymentSku"
    $capacity = Get-PositiveParameter "${kind}Capacity"
    if ($skuName -cnotin @('GlobalStandard', 'Standard')) {
        throw "$kind deployment must use pay-as-you-go Standard or GlobalStandard."
    }
    $matches = @($models | Where-Object {
        $_.kind -eq 'AIServices' -and $_.skuName -eq 'S0' -and
        $_.model.format -eq 'OpenAI' -and $_.model.name -ceq $name -and $_.model.version -ceq $version
    })
    if ($matches.Count -ne 1) {
        throw "Model $name/$version is not uniquely available for AIServices/S0 in $location. Use az cognitiveservices model list --location $location and choose supported parameters."
    }
    if ($kind -eq 'chat' -and $matches[0].model.capabilities.chatCompletion -ne 'true') {
        throw "Model $name/$version does not support the Chat Completions API required by this gateway."
    }
    if ($matches[0].model.lifecycleStatus -eq 'Deprecated') {
        throw "Model $name/$version is deprecated; select a supported version."
    }
    # A base model and its fine-tuning variant can share the same deployment SKU name.
    $baseUsageName = "OpenAI.$skuName.$name"
    $sku = @($matches[0].model.skus | Where-Object {
        $_.name -ceq $skuName -and $_.usageName -eq $baseUsageName
    })
    if ($sku.Count -ne 1) {
        throw "Base-model SKU $skuName for $name/$version with quota '$baseUsageName' is not uniquely available for AIServices/S0 in $location. Use az cognitiveservices model list --location $location and choose supported parameters."
    }
    if ($sku[0].deprecationDate -and [DateTimeOffset]$sku[0].deprecationDate -le [DateTimeOffset]::UtcNow) {
        throw "Model $name/$version SKU $skuName is deprecated; select a supported version."
    }
    if ($matches[0].model.deprecation.inference -and
        [DateTimeOffset]$matches[0].model.deprecation.inference -le [DateTimeOffset]::UtcNow) {
        throw "Model $name/$version inference is retired; select a supported version."
    }
    $limits = $sku[0].capacity
    if ($null -ne $limits.minimum -and $capacity -lt $limits.minimum -or
        $null -ne $limits.maximum -and $capacity -gt $limits.maximum -or
        $null -ne $limits.step -and $limits.step -gt 0 -and ($capacity - $limits.minimum) % $limits.step -ne 0) {
        throw "$kind capacity $capacity is outside the model SKU's allowed capacity range/step."
    }
    $usageName = $sku[0].usageName
    if ([string]::IsNullOrWhiteSpace($usageName)) {
        throw "No quota identifier returned for $name/$version/$skuName; cannot verify quota."
    }
    $deploymentName = if ($kind -eq 'chat') { 'chat' } else { 'embeddings' }
    $existing = @($ExistingDeployments | Where-Object {
        $_.name -eq $deploymentName -and $_.properties.model.name -eq $name -and
        $_.properties.model.version -eq $version -and $_.sku.name -eq $skuName
    })
    $allocated = if ($existing.Count -eq 1) { [int]$existing[0].sku.capacity } else { 0 }
    if ($matches[0].model.lifecycleStatus -eq 'Deprecating' -and
        ($existing.Count -ne 1 -or $allocated -ne $capacity)) {
        throw "Model $name/$version is deprecating and cannot be used for a new or resized deployment. Select a supported model/version."
    }
    $quotaRequested[$usageName] += [Math]::Max(0, $capacity - $allocated)
    Write-Host "Model available: $name / $version / $skuName / capacity $capacity (AIServices/S0; quota: $usageName)."
}
foreach ($usageName in $quotaRequested.Keys) {
    $usage = @($usages | Where-Object { $_.name.value -eq $usageName })
    if ($usage.Count -ne 1 -or $null -eq $usage[0].limit -or $null -eq $usage[0].currentValue) {
        throw "Unable to verify quota '$usageName' in $location."
    }
    if ($usage[0].limit - $usage[0].currentValue -lt $quotaRequested[$usageName]) {
        throw "Insufficient available quota '$usageName' in $location; need $($quotaRequested[$usageName]) additional capacity units. Lower capacity or request quota."
    }
}
Write-Host 'Quota verified for additional capacity; unchanged matching deployments in the recorded Foundry account retain their allocation.'
Write-Warning 'Provider/model availability is not a capacity reservation. Review azd preview and current Standard v2/Managed Redis regional SKU availability before provisioning.'
