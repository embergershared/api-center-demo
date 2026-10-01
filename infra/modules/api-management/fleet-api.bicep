targetScope = 'resourceGroup'

param apiManagementName string

resource service 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apiManagementName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: service
  name: 'fleet-vehicle-api'
  properties: {
    displayName: 'Fleet Vehicle API'
    path: 'fleet'
    protocols: ['https']
    subscriptionRequired: false
    format: 'openapi+json'
    value: loadTextContent('../../../samples/fleet-vehicle-v2.json')
  }
}
