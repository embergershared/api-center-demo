targetScope = 'resourceGroup'

@minLength(2)
@maxLength(64)
param name string
param projectName string
param location string
param tags object
param chatModelName string
param chatModelVersion string
@allowed(['GlobalStandard', 'Standard'])
param chatDeploymentSku string
@minValue(1)
param chatCapacity int
param embeddingModelName string
param embeddingModelVersion string
@allowed(['GlobalStandard', 'Standard'])
param embeddingDeploymentSku string
@minValue(1)
param embeddingCapacity int

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: name
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Utility AI demo'
    description: 'Synthetic utility API governance and AI gateway demonstrations; not operational decision support.'
  }
}

resource chat 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: 'chat'
  sku: {
    name: chatDeploymentSku
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  // Project and model writes share an account-level operation lock.
  dependsOn: [
    project
  ]
}

resource embeddings 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: 'embeddings'
  sku: {
    name: embeddingDeploymentSku
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  dependsOn: [
    chat
  ]
}

output id string = account.id
output name string = account.name
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output projectEndpoint string = uri(account.properties.endpoints['AI Foundry API'], 'api/projects/${project.name}')
output openAIEndpoint string = account.properties.endpoints['OpenAI Language Model Instance API']
output chatDeploymentName string = chat.name
output embeddingDeploymentName string = embeddings.name
