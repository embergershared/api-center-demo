targetScope = 'resourceGroup'

param apiManagementName string
param apiManagementPrincipalId string
param foundryName string
param projectPrincipalId string
param redisName string
param applicationInsightsName string
param chatDeploymentName string
param embeddingDeploymentName string
param cachePartition string
@minValue(1)
param tokensPerMinute int
@minValue(1)
param tokensPerDay int

resource service 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apiManagementName
}
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}
resource cache 'Microsoft.Cache/redisEnterprise@2025-07-01' existing = {
  name: redisName
}
resource database 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' existing = {
  parent: cache
  name: 'default'
}
resource insights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

var openAIUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
resource modelAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, apiManagementPrincipalId, openAIUserRole)
  properties: {
    principalId: apiManagementPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: openAIUserRole
  }
}

resource projectModelAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, projectPrincipalId, openAIUserRole)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: openAIUserRole
  }
}

var metricsPublisherRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
resource metricsAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: insights
  name: guid(insights.id, apiManagementPrincipalId, metricsPublisherRole)
  properties: {
    principalId: apiManagementPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: metricsPublisherRole
  }
}

resource externalCache 'Microsoft.ApiManagement/service/caches@2024-05-01' = {
  parent: service
  name: 'semantic-cache'
  properties: {
    // APIM cache resourceId requires an absolute management URL, not an ARM ID.
    resourceId: uri(environment().resourceManager, cache.id)
    useFromLocation: 'default'
    description: 'TLS-only Managed Redis with RediSearch; synthetic demo responses only.'
    connectionString: '${cache.properties.hostName}:10000,password=${database.listKeys().primaryKey},ssl=True,abortConnect=False'
  }
}

resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: service
  name: 'application-insights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: insights.id
    credentials: {
      connectionString: insights.properties.ConnectionString
      identityClientId: 'SystemAssigned'
    }
  }
  dependsOn: [
    metricsAccess
  ]
}

resource chatBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: service
  name: 'foundry-chat'
  properties: {
    protocol: 'http'
    url: uri(foundry.properties.endpoints['OpenAI Language Model Instance API'], 'openai/v1')
    description: 'Foundry OpenAI API using the gateway managed identity.'
  }
}

resource embeddingsBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: service
  name: 'foundry-embeddings'
  properties: {
    protocol: 'http'
    url: uri(foundry.properties.endpoints['OpenAI Language Model Instance API'], 'openai/deployments/${embeddingDeploymentName}/embeddings')
    credentials: {
      query: {
        'api-version': [
          '2024-10-21'
        ]
      }
    }
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: service
  name: 'utility-ai'
  properties: {
    displayName: 'Utility AI demonstration'
    description: 'Synthetic, non-operational utility glossary demo. Subscription authentication required.'
    path: 'ai'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    format: 'openapi+json'
    value: loadTextContent('openapi.json')
  }
}

resource diagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: api
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    logClientIp: false
    metrics: true
    httpCorrelationProtocol: 'W3C'
    verbosity: 'error'
    frontend: {
      request: {
        body: { bytes: 0 }
        headers: []
      }
      response: {
        body: { bytes: 0 }
        headers: []
      }
    }
    backend: {
      request: {
        body: { bytes: 0 }
        headers: []
      }
      response: {
        body: { bytes: 0 }
        headers: []
      }
    }
  }
}

var modelPolicy = replace(loadTextContent('ai-policy.xml'), '__MODEL_PARTITION__', cachePartition)
var policy = replace(
  replace(
    replace(modelPolicy, '__CHAT_DEPLOYMENT__', chatDeploymentName),
    '__TOKENS_PER_MINUTE__', string(tokensPerMinute)
  ),
  '__TOKENS_PER_DAY__', string(tokensPerDay)
)
resource aiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: policy
  }
  dependsOn: [
    modelAccess
    externalCache
    chatBackend
    embeddingsBackend
    diagnostic
  ]
}

resource demoSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: service
  name: 'utility-ai-demo'
  properties: {
    displayName: 'Utility AI demo only'
    scope: api.id
    state: 'active'
    allowTracing: false
  }
}

output apiName string = api.name
output subscriptionName string = demoSubscription.name
