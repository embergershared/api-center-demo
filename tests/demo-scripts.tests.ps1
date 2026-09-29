# Invoked by run-tests.ps1 inside its isolated fake-CLI/environment scope.
function Get-DemoArgument {
    param($Call, [string] $Name)
    $index = [array]::IndexOf($Call.arguments, $Name)
    Assert-True ($index -ge 0) "Missing command option $Name."
    $Call.arguments[$index + 1]
}

function Assert-DemoFilesRemoved {
    foreach ($call in $global:demoTestState.demoCalls) {
        foreach ($path in $call.paths) {
            Assert-True (-not (Test-Path -LiteralPath $path)) 'Demo JSON temporary file leaked.'
        }
    }
}

function spectral {
    Assert-True ($args[0] -eq 'lint') 'Unexpected Spectral command.'
    Assert-True ([System.IO.Path]::IsPathFullyQualified($args[1]) -and
        (Test-Path -LiteralPath $args[1])) 'Spectral input must use an existing absolute path.'
    Assert-True ($args[2] -eq '--ruleset' -and
        (Test-Path -LiteralPath $args[3])) 'Spectral ruleset path is invalid.'
    Assert-True ($args -contains 'json' -and $args -contains '--quiet' -and
        $args -contains '--fail-severity' -and $args[-1] -eq 'error') 'Spectral must emit a machine-readable report with an explicit error threshold.'
    $global:LASTEXITCODE = $global:demoTestState.spectralExitCode
    $global:demoTestState.spectralReport
}

$demoScripts = [ordered]@{
    '03-register-openapi-api.ps1' = 4
    '04-versions-and-deprecation.ps1' = 5
    '05-link-apim.ps1' = 4
    '06-environments-deployments.ps1' = 4
    '07-lint-analysis.ps1' = 4
    '08-portal-and-cli-demo.ps1' = 2
}
$demoResults = @{}
$demoLogs = @{}
Push-Location $PSScriptRoot
try {
    foreach ($scriptName in $demoScripts.Keys) {
        $global:demoTestState.demoCalls = @()
        $demoLogs[$scriptName] = & (Join-Path $root 'scripts' $scriptName) 6>&1
        Assert-True ($global:demoTestState.demoCalls.Count -eq $demoScripts[$scriptName]) "Unexpected command sequence in $scriptName."
        Assert-DemoFilesRemoved
        $demoResults[$scriptName] = $global:demoTestState.demoCalls

        for ($failureCall = 1; $failureCall -le $demoScripts[$scriptName]; $failureCall++) {
            $global:demoTestState.demoCalls = @()
            $global:demoTestState.demoFailureCall = $failureCall
            Assert-Throws { $null = & (Join-Path $root 'scripts' $scriptName) 6>&1 } 'Azure CLI exit code 42\):\s+ERROR: demo failure detail'
            Assert-True ($global:demoTestState.demoCalls.Count -eq $failureCall) "$scriptName continued after a failed command."
            Assert-DemoFilesRemoved
        }
        $global:demoTestState.demoFailureCall = 0
    }

    $calls = $demoResults['03-register-openapi-api.ps1']
    $properties = $calls[0].payloads['--custom-properties']
    Assert-True ($properties.lifecycleStage -eq 'production' -and
        $properties.businessOwner -eq 'Fleet Platform Team <fleet-platform@contoso.com>' -and
        $properties.complianceTag.Count -eq 1 -and
        $properties.complianceTag[0] -eq 'internal-only') 'Fleet custom properties changed.'
    Assert-True ((Get-DemoArgument $calls[0] '--title') -eq 'Fleet Vehicle API') 'API title was split.'
    Assert-True ((Get-DemoArgument $calls[1] '--lifecycle-stage') -eq 'deprecated') 'v1 lifecycle changed.'
    Assert-True ($calls[3].payloads['--value'].info.version -eq '1.0.0') 'Wrong v1 sample imported.'

    $calls = $demoResults['04-versions-and-deprecation.ps1']
    Assert-True ((Get-DemoArgument $calls[0] '--lifecycle-stage') -eq 'production' -and
        (Get-DemoArgument $calls[3] '--lifecycle-stage') -eq 'deprecated') 'Version lifecycles changed.'
    Assert-True ($calls[2].payloads['--value'].info.version -eq '2.0.0' -and
        $calls[4].payloads['--specification-path'].info.version -eq '2.0.0' -and
        (Get-DemoArgument $calls[4] '--path') -eq 'fleet') 'Wrong APIM import.'

    $calls = $demoResults['05-link-apim.ps1']
    Assert-True ("$($demoLogs['05-link-apim.ps1'])" -match 'azd env set API_CENTER_SKU Standard' -and
        "$($demoLogs['05-link-apim.ps1'])" -match 'does not confirm synchronization completion') 'Integration must explain the plan handoff without claiming sync completion.'
    Assert-True ((Get-DemoArgument $calls[2] '--query') -ceq
        "[?principalId=='$($global:demoTestValues.APIC_PRINCIPAL_ID)' && roleDefinitionName=='API Management Service Reader Role'].id | [0]") 'Reader query changed or was split.'
    Assert-True ((Get-DemoArgument $calls[3] '--azure-apim') -eq $global:demoTestValues.APIM_RESOURCE_ID) 'Integration must use the deployed APIM resource ID.'
    $global:demoTestState.demoCalls = @()
    $global:demoTestState.principalId = 'wrong'
    Assert-Throws { $null = & (Join-Path $root 'scripts\05-link-apim.ps1') 6>&1 } 'identity does not match'
    Assert-True ($global:demoTestState.demoCalls.Count -eq 2) 'Identity mismatch must block integration.'
    $global:demoTestState.principalId = $global:demoTestValues.APIC_PRINCIPAL_ID
    $global:demoTestState.demoCalls = @()
    $global:demoTestState.readerAssignment = ''
    Assert-Throws { $null = & (Join-Path $root 'scripts\05-link-apim.ps1') 6>&1 } 'missing its provisioned APIM Reader'
    Assert-True ($global:demoTestState.demoCalls.Count -eq 3) 'Missing Reader role must block integration.'
    $global:demoTestState.readerAssignment = 'reader-assignment'

    $calls = $demoResults['06-environments-deployments.ps1']
    Assert-True ("$($demoLogs['06-environments-deployments.ps1'])" -match 'catalog records, not separate azd environments' -and
        "$($demoLogs['04-versions-and-deprecation.ps1'])" -match 'not a working Fleet backend') 'Fleet catalog mappings must not be described as provisioned runtimes.'
    $types = @($calls[0..2] | ForEach-Object { Get-DemoArgument $_ '--type' })
    Assert-True (($types -join ',') -eq 'development,testing,production') 'Environment types changed.'
    Assert-True ($calls[3].payloads['--server'].runtimeUri -is [array] -and
        $calls[3].payloads['--server'].runtimeUri[0] -eq 'https://actual-gateway.example/fleet') 'Runtime URI payload changed.'
    Assert-True ((Get-DemoArgument $calls[3] '--environment-id') -eq '/workspaces/default/environments/prod' -and
        (Get-DemoArgument $calls[3] '--definition-id') -eq '/workspaces/default/apis/fleet-vehicle-api/versions/v2-0/definitions/openapi') 'Deployment resource references changed.'

    $calls = $demoResults['07-lint-analysis.ps1']
    Assert-True ("$($demoLogs['07-lint-analysis.ps1'])" -match 'expected error finding' -and
        "$($demoLogs['07-lint-analysis.ps1'])" -match 'not uploaded to API Center') 'Expected lint violations must be clearly distinguished from central analysis.'
    $properties = $calls[0].payloads['--custom-properties']
    Assert-True ($properties.lifecycleStage -eq 'development' -and
        $properties.businessOwner -eq 'Depot Operations Team') 'Legacy custom properties changed.'
    Assert-True ((Get-DemoArgument $calls[3] '--value') -like '*legacy-depot-charger-messy.json') 'Wrong legacy sample imported.'
    foreach ($scriptName in @('03-register-openapi-api.ps1', '04-versions-and-deprecation.ps1', '07-lint-analysis.ps1')) {
        $import = @($demoResults[$scriptName] | Where-Object { $_.payloads.ContainsKey('--specification') })
        Assert-True ($import.Count -eq 1 -and $import[0].payloads['--specification'].name -eq 'openapi' -and
            $import[0].payloads['--specification'].version -eq '3.0.1') 'OpenAPI specification details changed.'
    }

    $calls = $demoResults['08-portal-and-cli-demo.ps1']
    Assert-True ((Get-DemoArgument $calls[0] '--ids') -eq $global:demoTestValues.APIC_RESOURCE_ID -and
        (Get-DemoArgument $calls[0] '--query') -ceq 'properties.portalHostname' -and
        (Get-DemoArgument $calls[1] '--query') -ceq "[?customProperties.lifecycleStage=='production'].{title:title, id:name}") 'Portal demo queries changed.'
    Assert-True ("$($demoLogs['08-portal-and-cli-demo.ps1'])" -match 'https://actual-portal.example' -and
        "$($demoLogs['08-portal-and-cli-demo.ps1'])" -notmatch 'Full-profile AI') 'Core portal walkthrough must use the returned hostname and not require AI outputs.'

    try {
        $global:demoTestState.portalHostname = ''
        $log = & (Join-Path $root 'scripts\08-portal-and-cli-demo.ps1') 6>&1 3>&1
        Assert-True ("$log" -match 'has not returned a portal hostname' -and "$log" -notmatch 'Portal URL:') 'Missing hostname must warn rather than invent a URL.'
        $global:demoTestState.portalHostname = 'https://invalid.example/path'
        Assert-Throws { & (Join-Path $root 'scripts\08-portal-and-cli-demo.ps1') 6>&1 } 'invalid API Center portal hostname'
        $global:demoTestState.portalHostname = 'actual-portal.example'
        $global:demoTestValues.AZURE_DEPLOYMENT_PROFILE = 'full'
        $global:demoTestValues.AZURE_AI_PROJECT_ENDPOINT = 'https://foundry.example/api/projects/demo'
        $global:demoTestValues.AI_GATEWAY_URL = 'https://actual-gateway.example/ai/chat/completions'
        $global:demoTestState.demoCalls = @()
        $log = & (Join-Path $root 'scripts\08-portal-and-cli-demo.ps1') 6>&1 3>&1
        Assert-True ($global:demoTestState.demoCalls.Count -eq 3 -and "$log" -match 'AI API not yet visible' -and
            "$log" -match 'https://foundry.example/api/projects/demo' -and
            "$log" -match 'https://actual-gateway.example/ai/chat/completions' -and
            "$log" -match 'script 09 with -Confirm') 'Full profile must show actual outputs, pending synchronization, and a separate billable demo handoff.'
        $global:demoTestState.aiCatalogJson = '[{"name":"imported-ai","title":"Utility AI demonstration"}]'
        $log = & (Join-Path $root 'scripts\08-portal-and-cli-demo.ps1') 6>&1 3>&1
        Assert-True ("$log" -match 'Matching entries found' -and "$log" -notmatch 'AI API not yet visible') 'A matching title must request provenance verification rather than claim completed synchronization.'
        $global:demoTestState.aiCatalogJson = '{}'
        Assert-Throws { & (Join-Path $root 'scripts\08-portal-and-cli-demo.ps1') 6>&1 } 'did not return a catalog array'
        $global:demoTestState.aiCatalogJson = '[]'
        $global:demoTestState.demoCalls = @()
        $global:demoTestState.demoFailureCall = 3
        Assert-Throws { & (Join-Path $root 'scripts\08-portal-and-cli-demo.ps1') 6>&1 } 'Failed to check for the AI API.*Azure CLI exit code 42'
    }
    finally {
        $global:demoTestState.portalHostname = 'actual-portal.example'
        $global:demoTestState.demoFailureCall = 0
        $global:demoTestValues.AZURE_DEPLOYMENT_PROFILE = 'core'
        $global:demoTestValues.Remove('AZURE_AI_PROJECT_ENDPOINT')
        $global:demoTestValues.Remove('AI_GATEWAY_URL')
    }

    $originalReport = $global:demoTestState.spectralReport
    try {
        foreach ($case in @(
            @{ exitCode = 0; report = '[]'; pattern = 'no error-level violations' },
            @{ exitCode = 0; report = '[{"code":"warn-rule","path":[],"message":"Warning","severity":1}]'; pattern = '1 finding' }
        )) {
            $global:demoTestState.spectralExitCode = $case.exitCode
            $global:demoTestState.spectralReport = $case.report
            $log = & (Join-Path $root 'scripts\07-lint-analysis.ps1') 6>&1
            Assert-True ("$log" -match $case.pattern) 'Successful lint report was misclassified.'
        }
        foreach ($case in @(
            @{ exitCode = 2; report = 'Unable to load ruleset'; pattern = 'Spectral execution failed.*exit code 2' },
            @{ exitCode = 1; report = 'Unable to load ruleset'; pattern = 'did not return a valid JSON report' },
            @{ exitCode = 1; report = ''; pattern = 'did not return a valid JSON report' },
            @{ exitCode = 1; report = '{}'; pattern = 'report must be a JSON array' },
            @{ exitCode = 1; report = '[{}]'; pattern = 'invalid finding' },
            @{ exitCode = 1; report = '[]'; pattern = 'does not match' },
            @{ exitCode = 0; report = $originalReport; pattern = 'does not match' },
            @{ exitCode = 1; report = '[{"code":"invalid-ref","path":[],"message":"Reference missing","severity":0}]'; pattern = 'could not analyze the sample' }
        )) {
            $global:demoTestState.spectralExitCode = $case.exitCode
            $global:demoTestState.spectralReport = $case.report
            Assert-Throws { & (Join-Path $root 'scripts\07-lint-analysis.ps1') 6>&1 } $case.pattern
        }
        & {
            function Get-Command {
                param([string] $Name, $ErrorAction)
                Assert-True ($Name -eq 'spectral') 'Unexpected command discovery.'
                return $null
            }
            $log = & (Join-Path $root 'scripts\07-lint-analysis.ps1') 6>&1 3>&1
            Assert-True ("$log" -match 'Local linting skipped' -and "$log" -notmatch 'Local linting completed') 'Missing Spectral must be an explicit skip, not success.'
        }
    }
    finally {
        $global:demoTestState.spectralExitCode = 1
        $global:demoTestState.spectralReport = $originalReport
    }
}
finally {
    Pop-Location
}

if ($IsWindows) {
    & {
        . (Join-Path $root 'scripts\demo-cli.ps1')
        $fixtureDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "demo cli $([guid]::NewGuid())"
        $null = New-Item -ItemType Directory -Path $fixtureDirectory
        $shimPath = Join-Path $fixtureDirectory 'az.cmd'
        $recorderPath = Join-Path $fixtureDirectory 'record.ps1'
        $resultPath = Join-Path $fixtureDirectory 'arguments.json'
        $samplePath = Join-Path $fixtureDirectory 'sample api.json'
        try {
            $recorder = @'
$payloads = @{}
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i].StartsWith('@')) {
        $payloads[$args[$i - 1]] = Get-Content -LiteralPath $args[$i].Substring(1) -Raw | ConvertFrom-Json
    }
}
@{ arguments = $args; payloads = $payloads } | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'arguments.json') -Encoding utf8
if ($args -contains '--fail') {
    [Console]::Error.WriteLine('ERROR: native CLI failure detail')
    exit 19
}
'@
            Set-Content -LiteralPath $recorderPath -Value $recorder -Encoding utf8
            $pwshPath = (Get-Process -Id $PID).Path
            Set-Content -LiteralPath $shimPath -Value "@`"$pwshPath`" -NoProfile -File `"%~dp0record.ps1`" %*" -Encoding ascii
            Copy-Item -LiteralPath (Join-Path $root 'samples\fleet-vehicle-v1.json') -Destination $samplePath
            function az {
                & $shimPath @args
                $global:LASTEXITCODE = $LASTEXITCODE
            }
            $nativeArguments = @(
                'apic', 'api', 'create', '--title', 'Fleet Vehicle API',
                '--value', "@$samplePath",
                '--query', "[?principalId=='example' && roleDefinitionName=='API Management Service Reader Role'].id | [0]"
            )
            $jsonArguments = @{
                '--custom-properties' = "{`n  `"businessOwner`": `"Fleet Platform Team <fleet-platform@contoso.com>`"`n}"
                '--specification' = '{"name":"openapi","version":"3.0.1"}'
                '--server' = '{"runtimeUri":["https://example.com/fleet"]}'
            }
            $PSNativeCommandUseErrorActionPreference = $true
            Invoke-DemoAz -Arguments $nativeArguments -JsonArguments $jsonArguments -FailureMessage 'Native test failed'
            $record = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -AsHashtable
            Assert-True ((Get-DemoArgument $record '--title') -eq 'Fleet Vehicle API' -and
                (Get-DemoArgument $record '--query') -eq $nativeArguments[-1]) 'Windows cmd split a title or JMESPath query.'
            Assert-True ($record.payloads['--custom-properties'].businessOwner -eq 'Fleet Platform Team <fleet-platform@contoso.com>' -and
                $record.payloads['--specification'].version -eq '3.0.1' -and
                $record.payloads['--server'].runtimeUri[0] -eq 'https://example.com/fleet' -and
                $record.payloads['--value'].info.version -eq '1.0.0') 'Windows cmd corrupted JSON or a spaced sample path.'
            foreach ($name in $jsonArguments.Keys) {
                Assert-True (-not (Test-Path -LiteralPath (Get-DemoArgument $record $name).Substring(1))) 'Native success leaked temporary JSON.'
            }
            Assert-Throws {
                Invoke-DemoAz -Arguments ($nativeArguments + '--fail') -JsonArguments $jsonArguments -FailureMessage 'Native test failed'
            } 'Native test failed \(Azure CLI exit code 19\):\s+ERROR: native CLI failure detail'
            $record = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -AsHashtable
            foreach ($name in $jsonArguments.Keys) {
                Assert-True (-not (Test-Path -LiteralPath (Get-DemoArgument $record $name).Substring(1))) 'Native failure leaked temporary JSON.'
            }
        }
        finally {
            foreach ($path in @($shimPath, $recorderPath, $resultPath, $samplePath)) {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            }
            Remove-Item -LiteralPath $fixtureDirectory
        }
    }
}
