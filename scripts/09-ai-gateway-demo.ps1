[CmdletBinding(SupportsShouldProcess)]
param([securestring] $SubscriptionKey)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')
$values = Get-DeploymentEnvironment
Assert-DeploymentSubscription (Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID')
if ((Get-DeploymentValue $values 'AZURE_DEPLOYMENT_PROFILE') -ne 'full') {
    throw 'This demo requires a provisioned full profile. Run azd env refresh if outputs are stale.'
}
$url = Get-DeploymentValue $values 'AI_GATEWAY_URL'
$gateway = Get-DeploymentValue $values 'APIM_GATEWAY_URL'
$target = [uri]$url
if (-not $target.IsAbsoluteUri -or $target.Scheme -ne 'https' -or
    $url -cne "$($gateway.TrimEnd('/'))/ai/chat/completions") {
    throw 'AI_GATEWAY_URL does not match the deployed HTTPS APIM gateway.'
}
if (-not $PSCmdlet.ShouldProcess($url, 'Send two synthetic, non-streaming AI requests (may incur model and embeddings charges)')) { return }
if ($null -eq $SubscriptionKey) {
    $subscriptionName = Get-DeploymentValue $values 'AI_GATEWAY_SUBSCRIPTION_ID'
    $SubscriptionKey = Read-Host "Enter the APIM key for subscription '$subscriptionName' (not an Azure OpenAI key)" -AsSecureString
}
if ($SubscriptionKey.Length -eq 0) { throw 'An APIM subscription key is required.' }

$body = @{
    messages = @(
        @{ role = 'system'; content = 'You explain fictional utility glossary terms for a software demo. Never provide operational, outage restoration, equipment switching, or safety advice.' }
        @{ role = 'user'; content = 'For a fictional utility glossary, define an API catalog in one sentence.' }
    )
    stream = $false
    max_completion_tokens = 128
    reasoning_effort = 'none'
} | ConvertTo-Json -Depth 5

$headers = @{}
try {
    $headers['Ocp-Apim-Subscription-Key'] = [System.Net.NetworkCredential]::new('', $SubscriptionKey).Password
    $firstId = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -ContentType 'application/json' `
            -Body $body -TimeoutSec 90 -SkipHttpErrorCheck -MaximumRedirection 0
        $clock.Stop()
        if ($response.StatusCode -ne 200) {
            throw "AI gateway returned HTTP $($response.StatusCode). Check APIM tracing, subscription key, identity/RBAC propagation, model quota, and Redis connectivity. No successful cache test was recorded."
        }
        $completion = $response.Content | ConvertFrom-Json -Depth 20
        if ([string]::IsNullOrWhiteSpace($completion.id) -or @($completion.choices).Count -eq 0) {
            throw 'The gateway did not return a valid chat completion.'
        }
        [pscustomobject]@{
            Request = $attempt
            Status = [int]$response.StatusCode
            ElapsedMs = $clock.ElapsedMilliseconds
            CompletionId = $completion.id
            ReportedTokens = $completion.usage.total_tokens
            SameCompletionAsFirst = ($attempt -eq 2 -and $completion.id -eq $firstId)
        }
        if ($attempt -eq 1) {
            $firstId = $completion.id
            Start-Sleep -Seconds 2
        }
    }
    Write-Host 'A repeated completion ID suggests reuse; confirm semantic-cache lookup in APIM Test/Trace. Lower latency alone does not prove a hit.'
    Write-Host 'Cached responses can include original usage numbers. They are not evidence of newly billed chat tokens; embeddings requests still cost money.'
    Write-Host 'See docs\AI_GATEWAY.md for metrics, token-limit demonstration, and safe cache usage.'
}
finally {
    $headers.Clear()
}
