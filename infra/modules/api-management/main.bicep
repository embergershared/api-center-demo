targetScope = 'resourceGroup'

@minLength(1)
@maxLength(50)
param name string
param location string
param tags object
param publisherName string
param publisherEmail string
param apiCenterPrincipalId string

resource service 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'None'
    publisherName: publisherName
    publisherEmail: publisherEmail
  }
}

var readerRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '71522526-b88f-4d52-b57f-d31fc3546d0d'
)

resource apiCenterReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(service.id, apiCenterPrincipalId, readerRoleId)
  scope: service
  properties: {
    principalId: apiCenterPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: readerRoleId
  }
}

output id string = service.id
output name string = service.name
output gatewayUrl string = service.properties.gatewayUrl
output principalId string = service.identity.principalId
