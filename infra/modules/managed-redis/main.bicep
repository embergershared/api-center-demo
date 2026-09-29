targetScope = 'resourceGroup'

@minLength(1)
@maxLength(60)
param name string
param location string
param tags object
@allowed(['Balanced_B0', 'Balanced_B1'])
param sku string = 'Balanced_B0'
param highAvailability bool = false

resource cache 'Microsoft.Cache/redisEnterprise@2025-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    minimumTlsVersion: '1.2'
    highAvailability: highAvailability ? 'Enabled' : 'Disabled'
    publicNetworkAccess: 'Enabled'
  }
}

resource database 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' = {
  parent: cache
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    port: 10000
    clusteringPolicy: 'EnterpriseCluster'
    evictionPolicy: 'NoEviction'
    accessKeysAuthentication: 'Enabled'
    modules: [
      {
        name: 'RediSearch'
      }
    ]
  }
}

output name string = cache.name
output databaseId string = database.id
