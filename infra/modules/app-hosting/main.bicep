targetScope = 'resourceGroup'

@minLength(2)
@maxLength(60)
param containerAppsEnvironmentName string

@minLength(5)
@maxLength(50)
param containerRegistryName string

@minLength(3)
@maxLength(128)
param identityName string

@minLength(2)
@maxLength(32)
param apiAppName string

@minLength(2)
@maxLength(32)
param mcpAppName string

param location string
param tags object

@minLength(1)
param applicationInsightsConnectionString string

@minLength(4)
param logAnalyticsWorkspaceName string

@description('Set automatically by azd from SERVICE_<name>_RESOURCE_EXISTS. Preserves the currently deployed image across azd provision reruns.')
param apiAppExists bool = false

@description('Set automatically by azd from SERVICE_<name>_RESOURCE_EXISTS. Preserves the currently deployed image across azd provision reruns.')
param mcpAppExists bool = false

// Consumption-only Container Apps (no dedicated workload profiles) avoid the
// App Service VM-family quota that blocked Basic (B1) and PremiumV4 (P0V4)
// plans in this subscription; Consumption capacity is billed per vCPU-second
// and does not draw from the same quota pool.
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, identity.id, acrPullRoleId)
  scope: containerRegistry
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleId
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

var sharedEnv = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: applicationInsightsConnectionString
  }
]
var containerRegistryConfig = [
  {
    server: containerRegistry.properties.loginServer
    identity: identity.id
  }
]
var containerAppIdentity = {
  type: 'UserAssigned'
  userAssignedIdentities: {
    '${identity.id}': {}
  }
}

module currentImages './current-images.bicep' = {
  name: 'app-hosting-current-images'
  params: {
    apiAppName: apiAppName
    mcpAppName: mcpAppName
    apiAppExists: apiAppExists
    mcpAppExists: mcpAppExists
    placeholderImage: placeholderImage
  }
}

resource apiApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: apiAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'grid-telemetry-api' })
  identity: containerAppIdentity
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: containerRegistryConfig
    }
    template: {
      containers: [
        {
          name: 'grid-telemetry-api'
          image: currentImages.outputs.apiImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: sharedEnv
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  dependsOn: [
    acrPull
  ]
}

var apiAppUrl = 'https://${apiApp.properties.configuration.ingress.fqdn}'

resource mcpApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: mcpAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'grid-tools-mcp' })
  identity: containerAppIdentity
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: containerRegistryConfig
    }
    template: {
      containers: [
        {
          name: 'grid-tools-mcp'
          image: currentImages.outputs.mcpImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: concat(sharedEnv, [
            {
              name: 'GridTelemetryApi__BaseUrl'
              value: apiAppUrl
            }
          ])
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  dependsOn: [
    acrPull
  ]
}

var mcpAppUrl = 'https://${mcpApp.properties.configuration.ingress.fqdn}'

output apiAppName string = apiApp.name
output apiAppUrl string = apiAppUrl
output mcpAppName string = mcpApp.name
output mcpAppUrl string = mcpAppUrl
output containerAppsEnvironmentName string = containerAppsEnvironment.name
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output identityId string = identity.id
