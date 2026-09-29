# Provision infrastructure through the single azd/Bicep deployment path.
[CmdletBinding()]
param([switch] $PreviewOnly)

$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & (Join-Path $PSScriptRoot 'set-deployment-tags.ps1')
    & (Join-Path $PSScriptRoot 'preflight.ps1')
    & azd provision --preview --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'Deployment preview failed; no deployment was started.' }
    if ($PreviewOnly) { return }
    $confirmation = Read-Host 'Review the preview above. Provision this environment? [y/N]'
    if ($confirmation -notin @('y', 'Y')) {
        Write-Host 'Aborted.'
        return
    }
    & azd provision --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'Infrastructure provisioning failed.' }
    . (Join-Path $PSScriptRoot '00-vars.ps1')
}
finally {
    Pop-Location
}
