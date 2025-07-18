targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('The resource group name prefix')
param resourceGroupPrefix string = 'rg-aks-scale-to-zero'

@description('The AKS cluster name prefix')
param clusterNamePrefix string = 'aks-scale-to-zero'

@description('The Log Analytics workspace name prefix')
param logAnalyticsNamePrefix string = 'log-aks-scale-to-zero'

@description('The Azure Container Registry name prefix')
param acrNamePrefix string = 'craksscaletozero'

@description('The Key Vault name prefix')
param keyVaultNamePrefix string = 'kv-aks-s2z'

@description('The Kubernetes version')
param kubernetesVersion string = '1.32'

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environmentName
  Project: 'AKS-Scale-to-Zero'
  ManagedBy: 'Bicep'
}

// Generate unique suffixes for globally unique names
var uniqueSuffix = uniqueString(subscription().id, environmentName, location)
var resourceGroupName = '${resourceGroupPrefix}-${environmentName}'

// Create Resource Group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy Virtual Network first
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-${take(environmentName, 20)}'
  scope: resourceGroup
  params: {
    name: 'vnet-${take(environmentName, 20)}'
    location: location
    tags: tags
  }
}

// Deploy Log Analytics Workspace
module logAnalytics 'modules/log.bicep' = {
  name: 'log-${take(environmentName, 20)}'
  scope: resourceGroup
  params: {
    name: '${logAnalyticsNamePrefix}-${take(environmentName, 15)}'
    location: location
    tags: tags
  }
}

// Deploy Key Vault
module keyVault 'modules/keyvault.bicep' = {
  name: 'kv-${take(environmentName, 20)}'
  scope: resourceGroup
  params: {
    name: '${keyVaultNamePrefix}-${take(uniqueSuffix, 8)}'
    location: location
    tags: tags
    privateEndpointSubnetId: vnet.outputs.privateEndpointsSubnetId
    privateDnsZoneId: vnet.outputs.privateDnsZoneKeyVaultId
  }
}

// Deploy Azure Container Registry
module acr 'modules/acr.bicep' = {
  name: 'acr-${take(environmentName, 20)}'
  scope: resourceGroup
  params: {
    name: '${acrNamePrefix}${take(uniqueSuffix, 8)}'
    location: location
    tags: tags
    privateEndpointSubnetId: vnet.outputs.privateEndpointsSubnetId
    privateDnsZoneId: vnet.outputs.privateDnsZoneAcrId
  }
}

// Deploy AKS Cluster
module aks 'modules/aks.bicep' = {
  name: 'aks-${take(environmentName, 20)}'
  scope: resourceGroup
  params: {
    name: '${clusterNamePrefix}-${take(environmentName, 15)}'
    location: location
    kubernetesVersion: kubernetesVersion
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    vnetSubnetId: vnet.outputs.aksSubnetId
    tags: tags
  }
}

// Create a module for ACR role assignment since it needs to be scoped to the resource group
module acrRoleAssignment 'modules/acr-role-assignment.bicep' = {
  name: 'acr-role-${take(environmentName, 15)}'
  scope: resourceGroup
  params: {
    acrName: acr.outputs.registryName
    principalId: aks.outputs.kubeletIdentityObjectId
  }
}

// Deploy User Node Pool for Project A
module nodePoolProjectA 'modules/nodepool.bicep' = {
  name: 'np-a-${take(environmentName, 15)}'
  scope: resourceGroup
  params: {
    clusterName: aks.outputs.clusterName
    name: 'projecta'
    nodeCount: 0
    minCount: 0
    maxCount: 10
    vmSize: 'Standard_D2ds_v4'
    osDiskSizeGB: 64 // Increased from default 30GB to prevent eviction
    nodeLabels: {
      project: 'a'
      workload: 'user'
    }
    nodeTaints: []
    vnetSubnetId: vnet.outputs.aksSubnetId
    tags: tags
  }
}

// Deploy User Node Pool for Project B (GPU-enabled)
module nodePoolProjectB 'modules/nodepool.bicep' = {
  name: 'np-b-${take(environmentName, 15)}'
  scope: resourceGroup
  params: {
    clusterName: aks.outputs.clusterName
    name: 'projectb'
    nodeCount: 0
    minCount: 0
    maxCount: 5 // Reduced max count for GPU nodes to control costs
    vmSize: 'Standard_NC4as_T4_v3' // GPU-enabled VM with NVIDIA Tesla T4
    osDiskSizeGB: 128 // Increased for GPU workloads and container images
    nodeLabels: {
      project: 'b'
      workload: 'gpu'
    }
    nodeTaints: [
      'sku=gpu:NoSchedule'
    ]
    vnetSubnetId: vnet.outputs.aksSubnetId
    tags: tags
  }
}

// Outputs
output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.clusterName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.vaultName
