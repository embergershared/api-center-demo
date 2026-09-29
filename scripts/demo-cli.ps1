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
