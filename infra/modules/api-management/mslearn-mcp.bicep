targetScope = 'resourceGroup'

param apiManagementName string

@minLength(1)
@description('API Center portal hostname used to allow browser-based MCP testing.')
param apiCenterPortalHostname string

resource service 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apiManagementName
}

// APIM appends the MCP message path to this base URL.
var backendUrl = 'https://learn.microsoft.com/api'

resource backend 'Microsoft.ApiManagement/service/backends@2025-09-01-preview' = {
  parent: service
  name: 'mslearn-mcp'
  properties: {
    protocol: 'http'
    url: backendUrl
    description: 'Microsoft Learn public MCP endpoint for read-only documentation and code-sample search. No upstream credentials required.'
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: service
  name: 'mslearn-docs-mcp'
  properties: {
    type: 'mcp'
    displayName: 'Microsoft Learn Docs (MCP passthrough)'
    description: 'Governed passthrough to the public Microsoft Learn MCP server for read-only documentation and code-sample search. No upstream authentication is required.'
    path: 'learn-mcp'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    serviceUrl: backendUrl
    mcpProperties: {
      transportType: 'streamable'
      // The APIM runtime expects a dictionary; the published Bicep type still declares an array.
      endpoints: any({
        message: {
          name: 'message'
          uriTemplate: '/mcp'
        }
      })
    }
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(loadTextContent('mslearn-mcp-policy.xml'), '{{portal-origin}}', 'https://${apiCenterPortalHostname}')
  }
  dependsOn: [
    backend
  ]
}

output apiName string = api.name
output path string = api.properties.path
