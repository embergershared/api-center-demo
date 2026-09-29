# 07-lint-analysis.ps1 — run API analysis (Spectral-based linting) against the
# "messy" Legacy Depot Charger API to produce visible violations — the shift-left
# governance moment of the demo.
#
# Registers a sample and optionally runs local Spectral; central analysis is
# a separate setup step, not provisioned by this script or the Bicep deployment.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
. (Join-Path $PSScriptRoot 'demo-cli.ps1')
$SamplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'samples'
$specificationPath = Join-Path $SamplesDir 'legacy-depot-charger-messy.json'

Write-Host "==> (A) Registering the messy API in the catalog"
Write-Host '    Portal analysis requires a separately configured analyzer; importing alone does not enable it.'
$customProperties = '{
    "lifecycleStage": "development",
    "businessOwner": "Depot Operations Team"
  }'
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', 'legacy-depot-charger-api',
    '--title', 'Legacy Depot Charger API',
    '--type', 'rest',
    '-o', 'table'
) -JsonArguments @{ '--custom-properties' = $customProperties } `
    -FailureMessage 'Failed to create the legacy depot charger API'

Invoke-DemoAz -Arguments @(
    'apic', 'api', 'version', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', 'legacy-depot-charger-api',
    '--version-id', 'v1-0',
    '--title', 'v1',
    '--lifecycle-stage', 'development',
    '-o', 'table'
) -FailureMessage "Failed to create the legacy API version 'v1'"

Invoke-DemoAz -Arguments @(
    'apic', 'api', 'definition', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', 'legacy-depot-charger-api',
    '--version-id', 'v1-0',
    '--definition-id', 'openapi',
    '--title', 'OpenAPI 3.0',
    '-o', 'table'
) -FailureMessage 'Failed to create the legacy API definition'

Invoke-DemoAz -Arguments @(
    'apic', 'api', 'definition', 'import-specification',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', 'legacy-depot-charger-api',
    '--version-id', 'v1-0',
    '--definition-id', 'openapi',
    '--format', 'inline',
    '--value', "@$specificationPath",
    '-o', 'table'
) -JsonArguments @{ '--specification' = '{"name":"openapi","version":"3.0.1"}' } `
    -FailureMessage 'Failed to import the legacy OpenAPI specification'

Write-Host ""
Write-Host "==> (B) Running Spectral locally for instant, visible lint output"
if (-not (Get-Command spectral -ErrorAction SilentlyContinue)) {
    Write-Warning 'Local linting skipped: Spectral CLI not found. Install it with: npm install -g @stoplight/spectral-cli'
} else {
    # Spectral uses exit 1 for both findings and execution failures; require a report.
    $PSNativeCommandUseErrorActionPreference = $false
    $output = & spectral lint $specificationPath --ruleset (Join-Path $SamplesDir '.spectral.yaml') `
        --format json --quiet --fail-severity error 2>&1
    $lintExitCode = $LASTEXITCODE
    $report = $output -join [Environment]::NewLine
    if ($lintExitCode -notin @(0, 1)) {
        throw "Spectral execution failed (exit code $lintExitCode):$([Environment]::NewLine)$report"
    }
    if ([string]::IsNullOrWhiteSpace($report)) {
        throw "Spectral did not return a valid JSON report (exit code $lintExitCode): output was empty."
    }
    try {
        $findings = ConvertFrom-Json -InputObject $report -NoEnumerate -ErrorAction Stop
    }
    catch {
        throw "Spectral did not return a valid JSON report (exit code $lintExitCode):$([Environment]::NewLine)$report"
    }
    if ($findings -isnot [array]) { throw 'Spectral report must be a JSON array of findings.' }
    foreach ($finding in $findings) {
        if ([string]::IsNullOrWhiteSpace($finding.code) -or
            [string]::IsNullOrWhiteSpace($finding.message) -or
            $finding.severity -notin @(0, 1, 2, 3) -or $finding.path -isnot [array]) {
            throw 'Spectral returned an invalid finding; local linting could not be verified.'
        }
        if ($finding.code -in @('parser', 'invalid-ref', 'unrecognized-format')) {
            throw "Spectral could not analyze the sample: $($finding.code): $($finding.message)"
        }
    }
    $errorCount = @($findings | Where-Object severity -EQ 0).Count
    if (($lintExitCode -eq 1) -ne ($errorCount -gt 0)) {
        throw "Spectral exit code $lintExitCode does not match its reported error findings."
    }
    $findings | Select-Object severity, code, @{ Name = 'path'; Expression = { $_.path -join '.' } }, message |
        Format-Table -Wrap | Out-Host
    if ($lintExitCode -eq 1) {
        Write-Host "Local linting completed with $errorCount expected error finding(s) for the deliberately messy sample."
    }
    else {
        Write-Host "Local linting completed with $($findings.Count) finding(s) and no error-level violations."
    }
}

Write-Host ""
Write-Host "==> Talk track: point out missing operationId, missing descriptions, non-semver version,"
Write-Host '    and any other reported findings. These local results are not uploaded to API Center.'
Write-Host '    Configure central analysis separately before demonstrating in-portal analysis results.'
