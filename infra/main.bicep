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

@description('API Center defaults to Standard. Set Free explicitly only when its feature limits are acceptable.')
@allowed(['Free', 'Standard'])
param apiCenterSku string = 'Standard'

@description('Foundry/model region; defaults to the catalog region. Check model and quota availability before provisioning.')
param aiLocation string = location
param cacheLocation string = location
@description('Container Apps environment/apps region. Defaults to West US 3 because some subscriptions have zero App Service VM quota (Basic B1, PremiumV4 P0V4) in East US and East US 2, the API Center/APIM region. Consumption Container Apps avoid that VM-family quota entirely. Must remain independent of `location` for those subscriptions.')
param appHostingLocation string = 'westus3'
@description('Set automatically by azd from SERVICE_GRID_TELEMETRY_API_RESOURCE_EXISTS. Preserves the currently deployed image across azd provision reruns.')
param apiAppExists bool = false
@description('Set automatically by azd from SERVICE_GRID_TOOLS_MCP_RESOURCE_EXISTS. Preserves the currently deployed image across azd provision reruns.')
param mcpAppExists bool = false
param chatModelName string = 'gpt-5.6-luna'
param chatModelVersion string = '2026-07-09'
@allowed(['GlobalStandard', 'Standard'])
param chatDeploymentSku string = 'GlobalStandard'
@minValue(1)
param chatCapacity int = 10
param embeddingModelName string = 'text-embedding-3-small'
param embeddingModelVersion string = '1'
@allowed(['GlobalStandard', 'Standard'])
param embeddingDeploymentSku string = 'GlobalStandard'
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
var containerAppsEnvironmentName = azName(abbreviations.containerAppsEnvironment, locationCodeFor(appHostingLocation), subscriptionCode, environmentName, '')
var containerRegistryName = globalName(
  abbreviations.containerRegistry,
  locationCodeFor(appHostingLocation),
  subscriptionCode,
  environmentName,
  take(uniqueString(subscription().id, environmentName, appHostingLocation), 4),
  '',
  24
)
var identityName = azName(abbreviations.managedIdentity, locationCodeFor(appHostingLocation), subscriptionCode, environmentName, '')
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
var gridApiAppName = globalName(
  abbreviations.containerApp,
  locationCodeFor(appHostingLocation),
  subscriptionCode,
  environmentName,
  'api',
  '-',
  32
)
var gridMcpAppName = globalName(
  abbreviations.containerApp,
  locationCodeFor(appHostingLocation),
  subscriptionCode,
  environmentName,
  'mcp',
  '-',
  32
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

module fleetApi './modules/api-management/fleet-api.bicep' = {
  name: 'fleet-api'
  scope: resourceGroup
  params: {
    apiManagementName: apiManagement.outputs.name
  }
}

module mslearnMcp './modules/api-management/mslearn-mcp.bicep' = {
  name: 'mslearn-mcp'
  scope: resourceGroup
  params: {
    apiManagementName: apiManagement.outputs.name
    apiCenterPortalHostname: apiCenter.outputs.portalHostname
  }
}

module appHosting './modules/app-hosting/main.bicep' = {
  name: 'app-hosting'
  scope: resourceGroup
  params: {
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    identityName: identityName
    apiAppName: gridApiAppName
    mcpAppName: gridMcpAppName
    location: appHostingLocation
    tags: tags
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    apiAppExists: apiAppExists
    mcpAppExists: mcpAppExists
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
    apiCenterPrincipalId: apiCenter.outputs.principalId
    keyVaultName: globalName(abbreviations.keyVault, locationCode, subscriptionCode, environmentName, take(uniqueString(subscription().id, environmentName, location), 3), '-', 24)
    location: location
    tags: tags
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
output MSLEARN_MCP_URL string = '${apiManagement.outputs.gatewayUrl}/${mslearnMcp.outputs.path}/mcp'
output GRID_API_APP_URL string = appHosting.outputs.apiAppUrl
output GRID_API_APP_NAME string = appHosting.outputs.apiAppName
output GRID_MCP_APP_URL string = appHosting.outputs.mcpAppUrl
output GRID_MCP_APP_NAME string = appHosting.outputs.mcpAppName
output AZURE_APP_HOSTING_LOCATION string = appHostingLocation
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = appHosting.outputs.containerRegistryLoginServer
output AZURE_CONTAINER_ENVIRONMENT_NAME string = appHosting.outputs.containerAppsEnvironmentName
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
output MSLEARN_MCP_GATEWAY_URL string = '${apiManagement.outputs.gatewayUrl}/${mslearnMcp.outputs.path}'
output AI_GATEWAY_URL string = fullDemo ? '${apiManagement.outputs.gatewayUrl}/ai/chat/completions' : ''
output AI_GATEWAY_API_ID string = fullDemo ? aiGateway!.outputs.apiName : ''
output AI_GATEWAY_SUBSCRIPTION_ID string = fullDemo ? aiGateway!.outputs.subscriptionName : ''
