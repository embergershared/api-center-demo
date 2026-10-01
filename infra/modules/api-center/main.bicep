targetScope = 'resourceGroup'

@minLength(3)
@maxLength(90)
param name string
param location string
param tags object
@allowed(['Free', 'Standard'])
param skuName string = 'Standard'

resource service 'Microsoft.ApiCenter/services@2024-06-01-preview' = {
  name: name
  location: location
  tags: tags
  // The live API requires SKU on updates, but the published Bicep schema omits it.
  #disable-next-line BCP187
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

output id string = service.id
output name string = service.name
output principalId string = service.identity.principalId
// The live API returns this read-only property, but the published schema omits it.
#disable-next-line BCP053
output portalHostname string = service.properties.portalHostname
