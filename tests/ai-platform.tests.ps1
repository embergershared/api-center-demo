# Uses the compiled template and assertion helpers from run-tests.ps1; no Azure calls.
foreach ($name in @('foundry', 'redis', 'aiGateway')) {
    Assert-True ($resources[$name].condition -eq "[variables('fullDemo')]") "$name must be full-profile only."
    Assert-True ($resources[$name].resourceGroup -eq "[variables('resourceGroupName')]") "$name must use the demo group."
}
foreach ($name in @('foundry', 'redis')) {
    Assert-True ($resources[$name].properties.parameters.tags.value -eq "[variables('tags')]") "$name must receive common tags."
}
$foundryResources = $resources.foundry.properties.template.resources
$account = @($foundryResources | Where-Object type -EQ 'Microsoft.CognitiveServices/accounts')[0]
Assert-True ($account.kind -eq 'AIServices' -and $account.sku.name -eq 'S0' -and
    $account.properties.allowProjectManagement -and $account.properties.disableLocalAuth -and
    $account.properties.publicNetworkAccess -eq 'Enabled') 'Foundry account security or kind is incorrect.'
$project = @($foundryResources | Where-Object type -EQ 'Microsoft.CognitiveServices/accounts/projects')[0]
Assert-True ($project.identity.type -eq 'SystemAssigned' -and $project.tags -eq "[parameters('tags')]") 'Foundry project is missing identity/tags.'
$deployments = @($foundryResources | Where-Object type -EQ 'Microsoft.CognitiveServices/accounts/deployments')
Assert-True ($deployments.Count -eq 2) 'Both chat and embeddings deployments are required.'
$chatDeployment = @($deployments | Where-Object name -EQ "[format('{0}/{1}', parameters('name'), 'chat')]")[0]
$embeddingDeployment = @($deployments | Where-Object name -EQ "[format('{0}/{1}', parameters('name'), 'embeddings')]")[0]
Assert-True ($project.dependsOn -contains "[resourceId('Microsoft.CognitiveServices/accounts', parameters('name'))]") 'Foundry project must wait for the account.'
Assert-True ($chatDeployment.dependsOn -contains "[resourceId('Microsoft.CognitiveServices/accounts/projects', parameters('name'), parameters('projectName'))]") 'Chat must wait for the project to avoid concurrent Foundry account writes.'
Assert-True ($embeddingDeployment.dependsOn -contains "[resourceId('Microsoft.CognitiveServices/accounts/deployments', parameters('name'), 'chat')]") 'Embeddings must wait for chat to serialize all Foundry child writes.'
foreach ($deployment in $deployments) {
    Assert-True ($deployment.properties.model.format -eq 'OpenAI' -and
        $deployment.properties.versionUpgradeOption -eq 'NoAutoUpgrade') 'Model versions must be explicit and pinned.'
}
$redisResources = $resources.redis.properties.template.resources
$redisResource = @($redisResources | Where-Object type -EQ 'Microsoft.Cache/redisEnterprise')[0]
$database = @($redisResources | Where-Object type -EQ 'Microsoft.Cache/redisEnterprise/databases')[0]
Assert-True ($redisResource.properties.minimumTlsVersion -eq '1.2' -and
    $redisResource.properties.publicNetworkAccess -eq 'Enabled' -and
    $redisResource.tags -eq "[parameters('tags')]") 'Redis network/TLS/tag contract changed.'
Assert-True ($database.properties.clientProtocol -eq 'Encrypted' -and $database.properties.port -eq 10000 -and
    $database.properties.clusteringPolicy -eq 'EnterpriseCluster' -and
    $database.properties.evictionPolicy -eq 'NoEviction' -and
    $database.properties.modules[0].name -eq 'RediSearch') 'Semantic cache requires vector-capable TLS Redis.'
$gatewayResources = $resources.aiGateway.properties.template.resources
$cacheConnection = @($gatewayResources | Where-Object type -EQ 'Microsoft.ApiManagement/service/caches')[0]
Assert-True ($cacheConnection.properties.resourceId -eq "[uri(environment().resourceManager, resourceId('Microsoft.Cache/redisEnterprise', parameters('redisName')))]") 'APIM cache resourceId must be an absolute management URL for the selected Azure cloud, not a relative ARM resource ID.'
Assert-True ($cacheConnection.properties.connectionString -match 'listKeys' -and
    $cacheConnection.properties.connectionString -match 'ssl=True') 'Cache key must be obtained at deployment and used with TLS.'
$logger = @($gatewayResources | Where-Object type -EQ 'Microsoft.ApiManagement/service/loggers')[0]
Assert-True ($logger.properties.credentials.identityClientId -eq 'SystemAssigned') 'Telemetry must use managed identity.'
$roles = @($gatewayResources | Where-Object type -EQ 'Microsoft.Authorization/roleAssignments')
Assert-True ($roles.Count -eq 3 -and @($roles | Where-Object { $_.scope -match 'Microsoft.CognitiveServices/accounts' }).Count -eq 2 -and
    @($roles | Where-Object { $_.scope -match 'Microsoft.Insights/components' }).Count -eq 1) 'Gateway RBAC must be scoped to model and telemetry resources.'
$api = @($gatewayResources | Where-Object type -EQ 'Microsoft.ApiManagement/service/apis')[0]
Assert-True ($api.properties.subscriptionRequired -and ($api.properties.protocols -join ',') -eq 'https') 'AI API must require a subscription over HTTPS.'
$subscription = @($gatewayResources | Where-Object type -EQ 'Microsoft.ApiManagement/service/subscriptions')[0]
Assert-True ($subscription.properties.scope -match 'Microsoft.ApiManagement/service/apis' -and
    -not $subscription.properties.allowTracing -and -not $subscription.properties.Contains('primaryKey')) 'Demo subscription must be API-scoped with generated keys and tracing disabled.'
$diagnostic = @($gatewayResources | Where-Object type -EQ 'Microsoft.ApiManagement/service/apis/diagnostics')[0]
Assert-True ($diagnostic.properties.metrics -and -not $diagnostic.properties.logClientIp) 'Enable metrics without client IP logging.'
foreach ($side in @('frontend', 'backend')) {
    foreach ($direction in @('request', 'response')) {
        $settings = $diagnostic.properties[$side][$direction]
        Assert-True ($settings.body.bytes -eq 0 -and $settings.headers.Count -eq 0) 'Do not log AI bodies or headers.'
    }
}
foreach ($output in $template.outputs.Keys) {
    Assert-True ($output -notmatch 'KEY|SECRET|CONNECTION_STRING') "Secret-like output $output must not be exported to azd."
}

[xml]$policy = Get-Content (Join-Path $root 'infra\modules\api-management\ai-policy.xml') -Raw
$inbound = @($policy.policies.inbound.ChildNodes | ForEach-Object Name)
Assert-True ([array]::IndexOf($inbound, 'validate-content') -lt [array]::IndexOf($inbound, 'llm-semantic-cache-lookup')) 'Validate the payload before sending it to cache/embeddings.'
Assert-True ($policy.policies.inbound.'llm-semantic-cache-lookup'.'ignore-system-messages' -eq 'false' -and
    $policy.policies.inbound.'llm-semantic-cache-lookup'.'score-threshold' -eq '0.05') 'Cache safety settings changed.'
Assert-True ($policy.policies.inbound.'llm-semantic-cache-lookup'.'vary-by'[0] -eq '@(context.Subscription.Id)') 'Cache must be isolated per subscription.'
Assert-True ($policy.policies.inbound.'llm-semantic-cache-lookup'.'vary-by' -contains '__MODEL_PARTITION__') 'Cache partition must include configured model versions.'
Assert-True ($policy.policies.inbound.'llm-token-limit'.'token-quota-period' -eq 'Daily' -and
    $policy.policies.inbound.'llm-emit-token-metric'.namespace -eq 'UtilityAIGateway') 'Token control/metrics must be inbound.'
Assert-True ($policy.policies.outbound.'llm-semantic-cache-store'.duration -eq '60' -and
    -not $policy.policies.outbound.'llm-semantic-cache-store'.HasAttribute('cache-response')) 'Cache only successful completions for 60 seconds.'
Assert-True ($policy.policies.inbound.'rewrite-uri'.'copy-unmatched-params' -eq 'false' -and
    $policy.policies.inbound.'authentication-managed-identity'.resource -eq 'https://cognitiveservices.azure.com/') 'Route to fixed deployment using gateway identity.'
Assert-True ($policy.policies.inbound.'rewrite-uri'.template -eq '/chat/completions' -and
    $policy.policies.inbound.'set-body' -match 'body\["model"\] = "__CHAT_DEPLOYMENT__"' -and
    $policy.policies.inbound.'llm-semantic-cache-lookup'.'vary-by'[-1] -match '"max_completion_tokens"') 'The v1 backend must receive the fixed deployment and cache by completion limit.'
$chatBackend = @($gatewayResources | Where-Object { $_.type -eq 'Microsoft.ApiManagement/service/backends' -and $_.name -match 'foundry-chat' })[0]
Assert-True ($chatBackend.properties.url -match 'openai/v1') 'GPT-5 chat must use the OpenAI v1 backend.'
$spec = Get-Content (Join-Path $root 'infra\modules\api-management\openapi.json') -Raw | ConvertFrom-Json -AsHashtable
$schema = $spec.paths['/chat/completions'].post.requestBody.content['application/json'].schema
Assert-True ($schema.properties.stream.enum.Count -eq 1 -and $schema.properties.stream.enum[0] -eq $false -and
    $schema.properties.max_completion_tokens.maximum -eq 512 -and $schema.additionalProperties -eq $false -and
    $schema.properties.reasoning_effort.enum[0] -eq 'none' -and
    -not $schema.properties.Contains('temperature') -and -not $schema.properties.Contains('max_tokens')) 'Demo API must use bounded GPT-5 completions without unsupported sampling parameters.'
$schemaJson = $schema | ConvertTo-Json -Depth 20
$validPayload = @{
    messages = @(@{ role = 'user'; content = 'Define an API catalog.' })
    stream = $false; max_completion_tokens = 128; reasoning_effort = 'none'
}
Assert-True (Test-Json -Json ($validPayload | ConvertTo-Json -Depth 5) -Schema $schemaJson) 'GPT-5 request must pass API validation.'
foreach ($invalid in @(
    @{ max_completion_tokens = 513 }, @{ max_completion_tokens = 0 }, @{ reasoning_effort = 'high' },
    @{ temperature = 0 }, @{ max_tokens = 128 }, @{ stream = $true }, @{ model = 'other-deployment' }
)) {
    $payload = $validPayload.Clone()
    foreach ($key in $invalid.Keys) { $payload[$key] = $invalid[$key] }
    Assert-True (-not (Test-Json -Json ($payload | ConvertTo-Json -Depth 5) -Schema $schemaJson -ErrorAction SilentlyContinue)) 'Unsupported GPT-5 input must fail API validation.'
}

& {
    . (Join-Path $root 'scripts\deployment-context.ps1')
    $values = @{
        AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000001'
        AI_LOCATION = 'eastus'
        CACHE_LOCATION = 'eastus'
    }
    Assert-True ((Get-DeploymentParameterValue $values 'chatModelName') -eq
        $template.parameters.chatModelName.defaultValue) 'Script and Bicep model defaults drifted.'
    Assert-True ((Get-DeploymentParameterValue $values 'chatModelVersion') -eq
        $template.parameters.chatModelVersion.defaultValue) 'Script and Bicep version defaults drifted.'
    Assert-True ((Get-DeploymentParameterValue @{ CHAT_MODEL_NAME = '' } 'chatModelName') -eq
        $template.parameters.chatModelName.defaultValue) 'Blank model settings must use the shared default.'
    $global:aiTest = @{
        fail = $false; quota = 100; modelAvailable = $true; requests = 0; httpStatus = 200
        foundryAvailable = $true; baseSkuCopies = 1; retired = $false; deprecated = $false
        lifecycle = 'GenerallyAvailable'; chatSupported = 'true'
    }
    function az {
        $global:LASTEXITCODE = 0
        if ($global:aiTest.fail) { $global:LASTEXITCODE = 7; return }
        if ($args[0] -eq 'account') { return '00000000-0000-0000-0000-000000000001' }
        if ($args[1] -eq 'model') {
            $models = @(foreach ($accountKind in @('OpenAI', 'AIServices')) {
                if ($accountKind -eq 'AIServices' -and -not $global:aiTest.foundryAvailable) { continue }
                foreach ($definition in @(
                    @{ name = 'gpt-5.6-luna'; version = '2026-07-09'; sku = 'GlobalStandard' },
                    @{ name = 'text-embedding-3-small'; version = '1'; sku = 'Standard' }
                )) {
                    $usageName = "OpenAI.$($definition.sku).$($definition.name)"
                    $skus = @(for ($i = 0; $i -lt $global:aiTest.baseSkuCopies; $i++) {
                        @{
                            name = $definition.sku; usageName = $usageName
                            capacity = @{ minimum = 1; maximum = 100; step = 1 }
                            deprecationDate = $(if ($global:aiTest.deprecated) { '2000-01-01T00:00:00Z' })
                        }
                    })
                    $skus += @{
                        name = $definition.sku; usageName = "$usageName-finetune"
                        capacity = @{ minimum = 1; maximum = 1; step = 1 }
                        deprecationDate = '2000-01-01T00:00:00Z'
                    }
                    @{
                        kind = $accountKind; skuName = 'S0'
                        model = @{
                            format = 'OpenAI'; name = $definition.name; version = $definition.version; skus = $skus
                            lifecycleStatus = $global:aiTest.lifecycle
                            capabilities = @{ chatCompletion = $global:aiTest.chatSupported }
                            deprecation = @{
                                inference = $(if ($accountKind -eq 'OpenAI' -or $global:aiTest.retired) { '2000-01-01T00:00:00Z' })
                            }
                        }
                    }
                }
            })
            if (-not $global:aiTest.modelAvailable) { $models = @() }
            ConvertTo-Json -InputObject $models -Depth 12
        }
        elseif ($args[1] -eq 'usage') {
            @('OpenAI.GlobalStandard.gpt-5.6-luna', 'OpenAI.Standard.text-embedding-3-small') | ForEach-Object {
                @{ name = @{ value = $_ }; limit = $global:aiTest.quota; currentValue = 0 }
                @{ name = @{ value = "$_-finetune" }; limit = 1000; currentValue = 0 }
            } | ConvertTo-Json -Depth 5
        }
        else { throw "Unexpected AI preflight command: $args" }
    }
    function azd {
        $global:LASTEXITCODE = 0
        if ($args[1] -eq 'list') {
            ConvertTo-Json -InputObject @(@{ Name = 'test'; IsDefault = $true })
        }
        else {
            @{
                AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000001'
                AZURE_DEPLOYMENT_PROFILE = 'full'
                APIM_GATEWAY_URL = 'https://test.azure-api.net'
                AI_GATEWAY_URL = 'https://test.azure-api.net/ai/chat/completions'
            } | ConvertTo-Json
        }
    }
    function Invoke-WebRequest {
        param($Uri, $Method, $Headers, $ContentType, $Body, $TimeoutSec, [switch]$SkipHttpErrorCheck, $MaximumRedirection)
        $global:aiTest.requests++
        Assert-True ($Uri -eq 'https://test.azure-api.net/ai/chat/completions' -and
            $Headers['Ocp-Apim-Subscription-Key'] -eq 'test-key-not-a-secret' -and
            $MaximumRedirection -eq 0) 'Smoke test must target the real gateway and never redirect keys.'
        $payload = $Body | ConvertFrom-Json
        Assert-True ($payload.stream -eq $false -and $payload.max_completion_tokens -le 512 -and
            $payload.reasoning_effort -eq 'none' -and -not $payload.PSObject.Properties['temperature'] -and
            -not $payload.PSObject.Properties['max_tokens']) 'Smoke payload must obey GPT-5 API constraints.'
        @{
            StatusCode = $global:aiTest.httpStatus
            Content = '{"id":"completion-1","choices":[{"message":{"content":"synthetic"}}],"usage":{"total_tokens":42}}'
        }
    }
    function Start-Sleep { }
    try {
        & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values
        $global:aiTest.foundryAvailable = $false
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'not uniquely available for AIServices/S0'
        $global:aiTest.foundryAvailable = $true
        foreach ($copies in @(0, 2)) {
            $global:aiTest.baseSkuCopies = $copies
            Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'Base-model SKU.*not uniquely available'
        }
        $global:aiTest.baseSkuCopies = 1
        $global:aiTest.retired = $true
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'inference is retired'
        $global:aiTest.retired = $false
        $global:aiTest.deprecated = $true
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'SKU GlobalStandard is deprecated'
        $global:aiTest.deprecated = $false
        $global:aiTest.chatSupported = 'false'
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'does not support the Chat Completions API'
        $global:aiTest.chatSupported = 'true'
        $global:aiTest.lifecycle = 'Deprecated'
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'is deprecated'
        $global:aiTest.lifecycle = 'Deprecating'
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'new or resized deployment'
        $global:aiTest.lifecycle = 'GenerallyAvailable'
        $values.CHAT_CAPACITY = '0'
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'positive integer'
        $values.Remove('CHAT_CAPACITY')
        $values.REDIS_HIGH_AVAILABILITY = 'yes'
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'true or false'
        $values.Remove('REDIS_HIGH_AVAILABILITY')
        $global:aiTest.quota = 1
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'Insufficient available quota'
        $allocated = @(
            @{ name = 'chat'; properties = @{ model = @{ name = 'gpt-5.6-luna'; version = '2026-07-09' } }; sku = @{ name = 'GlobalStandard'; capacity = 10 } },
            @{ name = 'embeddings'; properties = @{ model = @{ name = 'text-embedding-3-small'; version = '1' } }; sku = @{ name = 'Standard'; capacity = 10 } }
        )
        & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values -ExistingDeployments $allocated
        $global:aiTest.lifecycle = 'Deprecating'
        & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values -ExistingDeployments $allocated
        $values.CHAT_CAPACITY = '11'
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values -ExistingDeployments $allocated } 'new or resized deployment'
        $values.Remove('CHAT_CAPACITY')
        $global:aiTest.lifecycle = 'GenerallyAvailable'
        $allocated[0].properties.model.version = 'old'
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values -ExistingDeployments $allocated } 'Insufficient available quota'
        $global:aiTest.quota = 100
        $global:aiTest.modelAvailable = $false
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'not uniquely available'
        $global:aiTest.modelAvailable = $true
        $global:aiTest.fail = $true
        Assert-Throws { & (Join-Path $root 'scripts\ai-preflight.ps1') -Values $values } 'AI preflight failed'
        $global:aiTest.fail = $false
        $key = ConvertTo-SecureString 'test-key-not-a-secret' -AsPlainText -Force
        $null = & (Join-Path $root 'scripts\09-ai-gateway-demo.ps1') -SubscriptionKey $key -WhatIf
        Assert-True ($global:aiTest.requests -eq 0) '-WhatIf must not send billable requests.'
        $result = @(& (Join-Path $root 'scripts\09-ai-gateway-demo.ps1') -SubscriptionKey $key)
        Assert-True ($result.Count -eq 2 -and $result[1].SameCompletionAsFirst) 'Smoke demo must compare two completions.'
        $global:aiTest.httpStatus = 429
        $global:aiTest.requests = 0
        Assert-Throws { & (Join-Path $root 'scripts\09-ai-gateway-demo.ps1') -SubscriptionKey $key } 'HTTP 429'
        Assert-True ($global:aiTest.requests -eq 1) 'Smoke demo must stop on a failed request.'
    }
    finally {
        Remove-Variable aiTest -Scope Global
    }
}
