targetScope = 'subscription'

import { abbreviations, locationCodeFor, azName, globalName } from './core/naming.bicep'
import { commonTags } from './core/tags.bicep'

@minLength(2)
@maxLength(32)
param environmentName string

@description('A region supporting API Center and Standard v2 API Management.')
param location string = 'eastus'

@minLength(2)
@maxLength(5)
param subscriptionCode string

@allowed(['core', 'full'])
param deploymentProfile string = 'full'

@description('Use Standard after the explicit API Center plan upgrade; keep Free for initial provisioning.')
@allowed(['Free', 'Standard'])
param apiCenterSku string = 'Free'

@description('Foundry/model region; defaults to the catalog region. Check model and quota availability before provisioning.')
param aiLocation string = location
param cacheLocation string = location
param chatModelName string = 'gpt-5.6-luna'
param chatModelVersion string = '2026-07-09'
@allowed(['GlobalStandard', 'Standard'])
param chatDeploymentSku string = 'GlobalStandard'
@minValue(1)
param chatCapacity int = 10
param embeddingModelName string = 'text-embedding-3-small'
param embeddingModelVersion string = '1'
@allowed(['GlobalStandard', 'Standard'])
param embeddingDeploymentSku string = 'Standard'
@minValue(1)
param embeddingCapacity int = 10
@allowed(['Balanced_B0', 'Balanced_B1'])
param redisSku string = 'Balanced_B0'
@description('Demo-only non-HA default has no availability SLA and may lose cached entries.')
param redisHighAvailability bool = false
@minValue(1)
param tokensPerMinute int = 5000
@minValue(1)
param tokensPerDay int = 100000

@minLength(1)
param repository string

@minLength(25)
@maxLength(25)
param createdOn string

@minLength(25)
@maxLength(25)
param lastUpdatedOn string

param owner string = ''
param costCenter string = ''

@minLength(1)
param publisherName string

@minLength(1)
param publisherEmail string

var locationCode = locationCodeFor(location)
var fullDemo = deploymentProfile == 'full'
var tags = commonTags(repository, environmentName, deploymentProfile, createdOn, lastUpdatedOn, owner, costCenter)
var resourceGroupName = azName(abbreviations.resourceGroup, locationCode, subscriptionCode, environmentName, '')
var apiCenterName = azName(abbreviations.apiCenter, locationCode, subscriptionCode, environmentName, '')
// APIM owns a globally unique DNS label; retain a subscription-derived suffix.
var apiManagementName = globalName(
  abbreviations.apiManagement,
  locationCode,
  subscriptionCode,
  environmentName,
  take(uniqueString(subscription().id, environmentName, location), 6),
  '-',
  50
)

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module monitoring './modules/monitoring/main.bicep' = {
  name: 'monitoring'
  scope: resourceGroup
  params: {
    name: azName(abbreviations.logAnalytics, locationCode, subscriptionCode, environmentName, '')
    applicationInsightsName: azName(
      abbreviations.applicationInsights,
      locationCode,
      subscriptionCode,
      environmentName,
      ''
    )
    location: location
    tags: tags
  }
}

module apiCenter './modules/api-center/main.bicep' = {
  name: 'api-center'
  scope: resourceGroup
  params: {
    name: apiCenterName
    location: location
    tags: tags
    skuName: apiCenterSku
  }
}

module apiManagement './modules/api-management/main.bicep' = {
  name: 'api-management'
  scope: resourceGroup
  params: {
    name: apiManagementName
    location: location
    tags: tags
    publisherName: publisherName
    publisherEmail: publisherEmail
    apiCenterPrincipalId: apiCenter.outputs.principalId
  }
}

module foundry './modules/foundry/main.bicep' = if (fullDemo) {
  name: 'foundry'
  scope: resourceGroup
  params: {
    name: globalName(abbreviations.aiServices, locationCodeFor(aiLocation), subscriptionCode, environmentName, take(uniqueString(subscription().id, environmentName, aiLocation), 3), '-', 64)
    projectName: azName(abbreviations.aiProject, locationCodeFor(aiLocation), subscriptionCode, environmentName, '')
    location: aiLocation
    tags: tags
    chatModelName: chatModelName
    chatModelVersion: chatModelVersion
    chatDeploymentSku: chatDeploymentSku
    chatCapacity: chatCapacity
    embeddingModelName: embeddingModelName
    embeddingModelVersion: embeddingModelVersion
    embeddingDeploymentSku: embeddingDeploymentSku
    embeddingCapacity: embeddingCapacity
  }
}

module redis './modules/managed-redis/main.bicep' = if (fullDemo) {
  name: 'managed-redis'
  scope: resourceGroup
  params: {
    name: globalName(abbreviations.managedRedis, locationCodeFor(cacheLocation), subscriptionCode, environmentName, take(uniqueString(subscription().id, environmentName, cacheLocation), 3), '-', 60)
    location: cacheLocation
    tags: tags
    sku: redisSku
    highAvailability: redisHighAvailability
  }
}

module aiGateway './modules/api-management/ai-gateway.bicep' = if (fullDemo) {
  name: 'ai-gateway'
  scope: resourceGroup
  params: {
    apiManagementName: apiManagement.outputs.name
    apiManagementPrincipalId: apiManagement.outputs.principalId
    foundryName: foundry!.outputs.name
    projectPrincipalId: foundry!.outputs.projectPrincipalId
    redisName: redis!.outputs.name
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    chatDeploymentName: foundry!.outputs.chatDeploymentName
    embeddingDeploymentName: foundry!.outputs.embeddingDeploymentName
    cachePartition: '${chatModelName}:${chatModelVersion}:${embeddingModelName}:${embeddingModelVersion}'
    tokensPerMinute: tokensPerMinute
    tokensPerDay: tokensPerDay
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_DEPLOYMENT_PROFILE string = deploymentProfile
output APIC_SERVICE string = apiCenter.outputs.name
output APIC_RESOURCE_ID string = apiCenter.outputs.id
output APIC_PRINCIPAL_ID string = apiCenter.outputs.principalId
output APIC_LOCATION string = location
output APIM_SERVICE string = apiManagement.outputs.name
output APIM_RESOURCE_ID string = apiManagement.outputs.id
output APIM_GATEWAY_URL string = apiManagement.outputs.gatewayUrl
output AZURE_LOG_ANALYTICS_WORKSPACE_ID string = monitoring.outputs.logAnalyticsWorkspaceId
output AZURE_APPLICATION_INSIGHTS_NAME string = monitoring.outputs.applicationInsightsName
output AZURE_AI_FOUNDRY_NAME string = fullDemo ? foundry!.outputs.name : ''
output AZURE_AI_FOUNDRY_RESOURCE_ID string = fullDemo ? foundry!.outputs.id : ''
output AZURE_AI_PROJECT_NAME string = fullDemo ? foundry!.outputs.projectName : ''
output AZURE_AI_PROJECT_ENDPOINT string = fullDemo ? foundry!.outputs.projectEndpoint : ''
output AZURE_OPENAI_ENDPOINT string = fullDemo ? foundry!.outputs.openAIEndpoint : ''
output AZURE_OPENAI_CHAT_DEPLOYMENT string = fullDemo ? foundry!.outputs.chatDeploymentName : ''
output AZURE_OPENAI_EMBEDDING_DEPLOYMENT string = fullDemo ? foundry!.outputs.embeddingDeploymentName : ''
output AZURE_MANAGED_REDIS_NAME string = fullDemo ? redis!.outputs.name : ''
output AI_GATEWAY_URL string = fullDemo ? '${apiManagement.outputs.gatewayUrl}/ai/chat/completions' : ''
output AI_GATEWAY_API_ID string = fullDemo ? aiGateway!.outputs.apiName : ''
output AI_GATEWAY_SUBSCRIPTION_ID string = fullDemo ? aiGateway!.outputs.subscriptionName : ''
