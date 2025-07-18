@description('Name of the Key Vault')
@minLength(3)
@maxLength(24)
param name string

@description('Location for the Key Vault')
param location string

@description('Tags to be applied to the Key Vault')
param tags object = {}

@description('Specifies the Azure Active Directory tenant ID')
param tenantId string = subscription().tenantId

@description('Specifies whether soft delete is enabled')
param enableSoftDelete bool = true

@description('Specifies the soft delete retention in days')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Specifies the SKU name')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Specifies whether Azure Virtual Machines are permitted to retrieve certificates')
param enabledForDeployment bool = false

@description('Specifies whether Azure Disk Encryption is permitted to retrieve secrets')
param enabledForDiskEncryption bool = false

@description('Specifies whether Azure Resource Manager is permitted to retrieve secrets')
param enabledForTemplateDeployment bool = false

@description('Enable RBAC authorization for Key Vault')
param enableRbacAuthorization bool = true

@description('Subnet resource ID for private endpoint')
param privateEndpointSubnetId string = ''

@description('Private DNS Zone ID for Key Vault')
param privateDnsZoneId string = ''

@description('Enable public network access')
param publicNetworkAccess string = privateEndpointSubnetId != '' ? 'Disabled' : 'Enabled'

// Create Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    enableRbacAuthorization: enableRbacAuthorization
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: privateEndpointSubnetId != '' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Create Private Endpoint for Key Vault if subnet is provided
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
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
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
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// Outputs
output vaultName string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
output vaultId string = keyVault.id
output privateEndpointId string = privateEndpointSubnetId != '' ? privateEndpoint.id : ''
