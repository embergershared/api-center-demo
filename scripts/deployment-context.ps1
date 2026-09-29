function Show-DeploymentEnvironmentSelection {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrEmpty($env:AZURE_ENV_NAME)) {
        Write-Host "azd environment: '$env:AZURE_ENV_NAME' (source: process AZURE_ENV_NAME)"
        return
    }

    Push-Location (Split-Path -Parent $PSScriptRoot)
    try {
        $json = & azd env list --output json
        if ($LASTEXITCODE -ne 0) { throw 'Unable to load the azd environment list.' }
        $environments = ($json -join [Environment]::NewLine) | ConvertFrom-Json
        $selected = @($environments | Where-Object { $_.IsDefault -eq $true })
        if ($selected.Count -eq 1 -and -not [string]::IsNullOrEmpty($selected[0].Name)) {
            Write-Host "azd environment: '$($selected[0].Name)' (source: project default / azd env select)"
        }
        else {
            Write-Host 'azd environment: <not selected> (source: no process AZURE_ENV_NAME or unique project default; azd will resolve selection)'
        }
    }
    finally {
        Pop-Location
    }
}

function Get-DeploymentEnvironment {
    [CmdletBinding()]
    param()

    Push-Location (Split-Path -Parent $PSScriptRoot)
    try {
        Show-DeploymentEnvironmentSelection
        $json = & azd env get-values --output json
        if ($LASTEXITCODE -ne 0) { throw 'Unable to load the selected azd environment.' }
        # Preserve ISO timestamps as strings across PowerShell versions.
        $document = [System.Text.Json.JsonDocument]::Parse(($json -join [Environment]::NewLine))
        try {
            if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
                throw 'azd did not return an environment object.'
            }
            $values = @{}
            foreach ($property in $document.RootElement.EnumerateObject()) {
                if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                    throw "azd value '$($property.Name)' is not a string."
                }
                $values[$property.Name] = $property.Value.GetString()
            }
            return $values
        }
        finally {
            $document.Dispose()
        }
    }
    finally {
        Pop-Location
    }
}

function Assert-DeploymentSubscription {
    param([Parameter(Mandatory)][string] $SubscriptionId)

    $active = & az account show --query id --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the active Azure CLI subscription. Run az login.' }
    if ($active.Trim() -ne $SubscriptionId) {
        throw "Azure CLI and azd subscriptions differ. Run: az account set --subscription $SubscriptionId"
    }
}

function Get-DeploymentValue {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Values,
        [Parameter(Mandatory)][string] $Name
    )
    if (-not $Values.Contains($Name) -or [string]::IsNullOrWhiteSpace([string]$Values[$Name])) {
        throw "Missing azd value '$Name'. Configure the environment or run azd provision / azd env refresh."
    }
    return [string]$Values[$Name]
}

function Get-DeploymentParameterBindings {
    [CmdletBinding()]
    param()

    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'infra\main.parameters.json'
    $parameters = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable).parameters
    foreach ($parameter in $parameters.GetEnumerator()) {
        if ($parameter.Value.value -cnotmatch '^\$\{(?<name>[A-Z0-9_]+)(?:=(?<default>[^}]*))?\}$') {
            throw "Unsupported environment expression for '$($parameter.Key)'."
        }
        [pscustomobject]@{
            ParameterName = $parameter.Key
            EnvironmentName = $Matches['name']
            HasDefault = $Matches.ContainsKey('default')
            DefaultValue = $Matches['default']
        }
    }
}

function Get-DeploymentParameterValue {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Values,
        [Parameter(Mandatory)][string] $ParameterName
    )
    $binding = Get-DeploymentParameterBindings | Where-Object ParameterName -CEQ $ParameterName
    if ($null -eq $binding) { throw "Unknown deployment parameter '$ParameterName'." }
    $key = $binding.EnvironmentName
    if ($Values.Contains($key) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$key])) {
        return [string]$Values[$key]
    }
    if ($binding.HasDefault) { return [string]$binding.DefaultValue }
    throw "Missing azd value '$key'. Run scripts\set-deployment-tags.ps1 or configure it with azd env set $key <value>."
}
