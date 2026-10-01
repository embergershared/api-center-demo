targetScope = 'resourceGroup'

param apiAppName string
param mcpAppName string
param apiAppExists bool
param mcpAppExists bool
param placeholderImage string

// Keep these reads outside the template that updates the same resource IDs.
resource apiApp 'Microsoft.App/containerApps@2024-03-01' existing = if (apiAppExists) {
  name: apiAppName
}

resource mcpApp 'Microsoft.App/containerApps@2024-03-01' existing = if (mcpAppExists) {
  name: mcpAppName
}

output apiImage string = apiAppExists ? apiApp!.properties.template.containers[0].image : placeholderImage
output mcpImage string = mcpAppExists ? mcpApp!.properties.template.containers[0].image : placeholderImage
