@description('Name of the AKS cluster')
@minLength(1)
@maxLength(63)
param name string

@description('Location for the AKS cluster')
param location string

@description('Kubernetes version')
param kubernetesVersion string

@description('Log Analytics workspace resource ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Virtual Network Subnet ID for AKS nodes')
param vnetSubnetId string

// Note: acrId parameter removed as ACR role assignment is handled separately

@description('Tags to be applied to the AKS cluster')
param tags object = {}

@description('DNS prefix for the cluster')
param dnsPrefix string = name

@description('System node pool configuration')
param systemNodePoolConfig object = {
  name: 'system'
  nodeCount: 2
  minCount: 1
  maxCount: 5
  vmSize: 'Standard_D2ds_v4'
  osDiskSizeGB: 64 // Increased from default 30GB to prevent eviction
  osDiskType: 'Managed'
  maxPods: 110
  osType: 'Linux'
  osSKU: 'Ubuntu'
  type: 'VirtualMachineScaleSets'
  mode: 'System'
  enableAutoScaling: true
  availabilityZones: []
}

@description('Network plugin to use')
@allowed([
  'azure'
  'kubenet'
])
param networkPlugin string = 'azure'

@description('Network plugin mode for Azure CNI')
@allowed([
  'overlay'
])
param networkPluginMode string = 'overlay'

@description('Network policy to use')
@allowed([
  'azure'
  'calico'
  'cilium'
])
param networkPolicy string = 'cilium'

@description('Network dataplane to use')
@allowed([
  'azure'
  'cilium'
])
param networkDataplane string = 'cilium'

@description('Service CIDR for cluster services')
param serviceCidr string = '10.0.0.0/16'

@description('DNS service IP (must be within serviceCidr)')
param dnsServiceIP string = '10.0.0.10'

@description('Pod CIDR for overlay network')
param podCidr string = '10.244.0.0/16'

@description('Enable RBAC on the cluster')
param enableRBAC bool = true

@description('AAD integration configuration')
param aadProfile object = {
  managed: true
  enableAzureRBAC: true
  adminGroupObjectIDs: []
}

// Create AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard' // Standard tier required for Cost Analysis Add-on ($0.10/hour)
  }
  identity: {
    type: 'SystemAssigned' // Enable system-assigned managed identity
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: dnsPrefix
    enableRBAC: enableRBAC

    // Node pools configuration
    agentPoolProfiles: [
      {
        name: systemNodePoolConfig.name
        count: systemNodePoolConfig.nodeCount
        minCount: systemNodePoolConfig.minCount
        maxCount: systemNodePoolConfig.maxCount
        vmSize: systemNodePoolConfig.vmSize
        osDiskSizeGB: systemNodePoolConfig.osDiskSizeGB
        osDiskType: systemNodePoolConfig.osDiskType
        maxPods: systemNodePoolConfig.maxPods
        type: systemNodePoolConfig.type
        mode: systemNodePoolConfig.mode
        osType: systemNodePoolConfig.osType
        osSKU: systemNodePoolConfig.osSKU
        enableAutoScaling: systemNodePoolConfig.enableAutoScaling
        availabilityZones: systemNodePoolConfig.availabilityZones
        vnetSubnetID: vnetSubnetId // VNet integration
        nodeTaints: []
        nodeLabels: {
          'node-pool': 'system'
        }
      }
    ]

    // Network configuration
    networkProfile: {
      networkPlugin: networkPlugin
      networkPluginMode: networkPluginMode // Enable overlay mode for Azure CNI
      networkPolicy: networkPolicy
      networkDataplane: networkDataplane // Use Cilium as dataplane
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      podCidr: podCidr // Pod CIDR for overlay network
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    // AAD integration
    aadProfile: aadProfile

    // Security profile
    securityProfile: {
      workloadIdentity: {
        enabled: true // Enable workload identity
      }
    }

    // OIDC issuer for workload identity
    oidcIssuerProfile: {
      enabled: true // Enable OIDC issuer
    }

    // Monitoring addon
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      azurepolicy: {
        enabled: true
      }
      azureKeyvaultSecretsProvider: {
        enabled: false // Disabled to minimize Key Vault usage
      }
    }

    // Metrics profile for cost analysis
    metricsProfile: {
      costAnalysis: {
        enabled: true // Enable Cost Analysis Add-on for namespace-level cost tracking
      }
    }

    // Auto upgrade configuration
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }

    // Disable local accounts for security
    disableLocalAccounts: false

    // API server access profile
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
  }
}

// Note: ACR role assignment should be done in main.bicep since the ACR might be in the same resource group
// The kubelet identity information is exposed as outputs for this purpose

// Outputs
output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output clusterFqdn string = aksCluster.properties.fqdn
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output kubeletIdentityClientId string = aksCluster.properties.identityProfile.kubeletidentity.clientId
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
