[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'naming.ps1')
. (Join-Path $PSScriptRoot 'deployment-context.ps1')

function Set-DeploymentValue {
    param([string] $Name, [string] $Value)
    & azd env set $Name $Value
    if ($LASTEXITCODE -ne 0) { throw "Unable to set azd environment value '$Name'." }
    $values[$Name] = $Value
}

function Initialize-DeploymentValue {
    param([string] $Name, [string] $Value, [string] $Source)
    if ([string]::IsNullOrWhiteSpace([string]$values[$Name])) {
        Set-DeploymentValue $Name $Value
        Write-Host "Initialized ${Name}: '$Value' (source: $Source)"
    }
}

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $values = Get-DeploymentEnvironment
    if ([string]::IsNullOrWhiteSpace($values['AZURE_SUBSCRIPTION_ID'])) {
        $activeSubscription = & az account show --query id --output tsv --only-show-errors
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($activeSubscription)) {
            throw 'Unable to determine AZURE_SUBSCRIPTION_ID. Run az login and az account set --subscription <id>, or azd env set AZURE_SUBSCRIPTION_ID <id>.'
        }
        Initialize-DeploymentValue 'AZURE_SUBSCRIPTION_ID' $activeSubscription.Trim() 'active Azure CLI subscription'
    }

    foreach ($binding in Get-DeploymentParameterBindings) {
        if ($binding.HasDefault -and -not [string]::IsNullOrWhiteSpace($binding.DefaultValue)) {
            Initialize-DeploymentValue $binding.EnvironmentName $binding.DefaultValue 'infra\main.parameters.json default'
        }
    }
    foreach ($key in @('AI_LOCATION', 'CACHE_LOCATION')) {
        Initialize-DeploymentValue $key (Get-DeploymentValue $values 'AZURE_LOCATION') 'AZURE_LOCATION'
    }
    $profile = Get-DeploymentValue $values 'DEPLOYMENT_PROFILE'
    if ($profile -cnotin @('core', 'full')) { throw 'This demo supports only DEPLOYMENT_PROFILE=core or full.' }
    if ($values['APIM_PUBLISHER_EMAIL'] -eq 'api-team@example.com') {
        Write-Warning 'APIM_PUBLISHER_EMAIL is a demo placeholder. Set a real address with azd env set APIM_PUBLISHER_EMAIL <email> to receive service notifications.'
    }

    $subscriptionId = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID'
    Assert-DeploymentSubscription $subscriptionId
    $subscriptionName = & az account show --subscription $subscriptionId --query name --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionName)) {
        throw "Unable to read the display name for subscription '$subscriptionId'."
    }
    $derivedCode = Get-SubscriptionCode $subscriptionName
    if ([string]::IsNullOrWhiteSpace($values['AZURE_SUBSCRIPTION_CODE'])) {
        Initialize-DeploymentValue 'AZURE_SUBSCRIPTION_CODE' $derivedCode 'Azure subscription display name'
    }
    else {
        $null = Assert-SubscriptionCode $subscriptionName $values['AZURE_SUBSCRIPTION_CODE']
    }

    if ([string]::IsNullOrWhiteSpace($values['AZURE_REPOSITORY'])) {
        Initialize-DeploymentValue 'AZURE_REPOSITORY' (Get-RepositoryName -Path (Split-Path -Parent $PSScriptRoot)) 'Git repository'
    }
    $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById(
        $(if ($IsWindows) { 'Eastern Standard Time' } else { 'America/New_York' })
    )
    $now = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $timeZone).ToString(
        'yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture
    )
    $createdOn = $values['AZURE_CREATED_ON']
    if ([string]::IsNullOrWhiteSpace($createdOn)) {
        Initialize-DeploymentValue 'AZURE_CREATED_ON' $now 'current Eastern time'
    }
    else {
        $parsed = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParseExact(
            $createdOn, 'yyyy-MM-ddTHH:mm:sszzz',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed
        )) {
            throw 'AZURE_CREATED_ON must be an ISO 8601 timestamp with the Eastern offset in effect at that instant.'
        }
        if ($parsed.Offset -ne $timeZone.GetUtcOffset($parsed.UtcDateTime)) {
            throw 'AZURE_CREATED_ON must use the Eastern offset in effect at that instant.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($values['AZURE_LAST_UPDATED_ON'])) {
        Initialize-DeploymentValue 'AZURE_LAST_UPDATED_ON' $now 'current Eastern time'
    }
    else {
        Set-DeploymentValue 'AZURE_LAST_UPDATED_ON' $now
    }
}
finally {
    Pop-Location
}
