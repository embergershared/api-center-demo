function Assert-DemoContainerAppDeployed {
    param(
        [Parameter(Mandatory)][string] $AppName,
        [Parameter(Mandatory)][string] $ServiceName
    )

    $output = Invoke-DemoAz -Arguments @(
        'containerapp', 'show', '--resource-group', $env:RESOURCE_GROUP,
        '--name', $AppName, '--query', 'properties.template.containers[].image', '--output', 'json'
    ) -FailureMessage "Failed to inspect Container App '$AppName'"
    $images = ($output -join [Environment]::NewLine) | ConvertFrom-Json -NoEnumerate
    if ($images -isnot [array] -or $images.Count -eq 0) {
        throw "Container App '$AppName' did not return any container images."
    }
    if (@($images | Where-Object { $_ -match '^mcr\.microsoft\.com/azuredocs/containerapps-helloworld(?=[:@]|$)' }).Count) {
        throw "Container App '$AppName' still runs the provisioning placeholder, not '$ServiceName'. Run 'azd deploy $ServiceName' in the selected environment, then rerun this registration script."
    }
}

function Invoke-CatalogRest {
    param(
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Id,
        [object] $Body
    )
    $arguments = @('rest', '--method', $Method, '--url',
        "https://management.azure.com${Id}?api-version=2024-06-01-preview", '--output', 'json')
    $jsonArguments = @{}
    if ($null -ne $Body) { $jsonArguments['--body'] = ConvertTo-Json -InputObject $Body -Depth 30 -Compress }
    $result = Invoke-DemoAz -Arguments $arguments -JsonArguments $jsonArguments -FailureMessage "Catalog $Method failed: $Id"
    if ($result) { return ($result -join [Environment]::NewLine) | ConvertFrom-Json }
}

function Invoke-DemoAz {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [System.Collections.IDictionary] $JsonArguments = @{},
        [Parameter(Mandatory)][string] $FailureMessage
    )

    $temporaryPaths = @()
    try {
        # Windows az.cmd cannot reliably transport inline JSON quotes or newlines.
        foreach ($name in $JsonArguments.Keys) {
            $path = [System.IO.Path]::GetTempFileName()
            $temporaryPaths += $path
            Set-Content -LiteralPath $path -Value $JsonArguments[$name] -Encoding utf8
            $Arguments += @($name, "@$path")
        }

        $PSNativeCommandUseErrorActionPreference = $false
        $output = az @Arguments --only-show-errors 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "$FailureMessage (Azure CLI exit code $LASTEXITCODE):$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
        }
        $output
    }
    finally {
        foreach ($path in $temporaryPaths) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}
