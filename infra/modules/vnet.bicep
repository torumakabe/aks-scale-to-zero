@description('Name of the Virtual Network')
@minLength(2)
@maxLength(64)
param name string

@description('Location for the Virtual Network')
param location string

@description('Tags to be applied to the Virtual Network')
param tags object = {}

@description('Address prefix for the Virtual Network')
param addressPrefix string = '10.224.0.0/16'

@description('Subnets configuration')
param subnets array = [
  {
    name: 'snet-aks'
    addressPrefix: '10.224.0.0/20' // 4094 addresses for AKS nodes
    delegations: []
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  {
    name: 'snet-private-endpoints'
    addressPrefix: '10.224.16.0/24' // 254 addresses for private endpoints
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Disabled'
  }
]

// Create Network Security Groups
resource aksNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${name}-aks'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // Allow inbound traffic from Azure Load Balancer
      {
        name: 'AllowAzureLoadBalancerInBound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource privateEndpointsNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${name}-pep'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// Create Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      for (subnet, i) in subnets: {
        name: subnet.name
        properties: {
          addressPrefix: subnet.addressPrefix
          delegations: subnet.delegations
          privateEndpointNetworkPolicies: subnet.privateEndpointNetworkPolicies
          privateLinkServiceNetworkPolicies: subnet.privateLinkServiceNetworkPolicies
          networkSecurityGroup: subnet.name == 'snet-aks'
            ? {
                id: aksNsg.id
              }
            : subnet.name == 'snet-private-endpoints'
                ? {
                    id: privateEndpointsNsg.id
                  }
                : null
        }
      }
    ]
  }
}

// Create Private DNS Zones for Azure services
resource privateDnsZoneAcr 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: tags
}

resource privateDnsZoneKeyVault 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

// Link Private DNS Zones to VNet
resource privateDnsZoneAcrLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZoneAcr
  name: 'vnetlink-${name}-acr'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource privateDnsZoneKeyVaultLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZoneKeyVault
  name: 'vnetlink-${name}-kv'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
output privateEndpointsSubnetId string = vnet.properties.subnets[1].id
output privateDnsZoneAcrId string = privateDnsZoneAcr.id
output privateDnsZoneKeyVaultId string = privateDnsZoneKeyVault.id
