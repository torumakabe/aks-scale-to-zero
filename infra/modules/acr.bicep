@description('Name of the Azure Container Registry')
@minLength(5)
@maxLength(50)
param name string

@description('Location for the Azure Container Registry')
param location string

@description('Tags to be applied to the Azure Container Registry')
param tags object = {}

@description('SKU name for the Azure Container Registry')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Premium'

@description('Enable admin user for the registry')
param adminUserEnabled bool = false // Disabled to enforce managed identity usage

@description('Enable public network access')
param publicNetworkAccess string = 'Enabled'

@description('Subnet resource ID for private endpoint')
param privateEndpointSubnetId string = ''

@description('Private DNS Zone ID for ACR')
param privateDnsZoneId string = ''

// Create Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: publicNetworkAccess
    networkRuleSet: {
      defaultAction: 'Allow'
    }
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
    }
    dataEndpointEnabled: false
    encryption: {
      status: 'disabled'
    }
    zoneRedundancy: 'Disabled'
  }
}

// Create Private Endpoint for ACR if subnet is provided
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = if (privateEndpointSubnetId != '') {
  name: 'pep-${name}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pep-${name}-connection'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

// Create Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (privateEndpointSubnetId != '' && privateDnsZoneId != '') {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// Get reference to AcrPull role definition
var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

// Outputs
output loginServer string = containerRegistry.properties.loginServer
output resourceId string = containerRegistry.id
output acrPullRoleId string = acrPullRoleDefinitionId
output registryName string = containerRegistry.name
output privateEndpointId string = privateEndpointSubnetId != '' ? privateEndpoint.id : ''
