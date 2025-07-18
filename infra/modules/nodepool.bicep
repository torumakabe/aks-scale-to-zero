// User Node Pool module for AKS - supports Scale to Zero
@description('The name of the AKS cluster')
param clusterName string

@description('The name of the node pool')
@maxLength(12)
@minLength(1)
param name string

@description('The initial number of nodes')
@minValue(0)
@maxValue(100)
param nodeCount int = 0

@description('The minimum number of nodes (0 for Scale to Zero)')
@minValue(0)
@maxValue(100)
param minCount int = 0

@description('The maximum number of nodes')
@minValue(1)
@maxValue(100)
param maxCount int = 10

@description('The size of the Virtual Machines')
param vmSize string = 'Standard_D2ds_v4'

@description('Node labels for pod scheduling')
param nodeLabels object = {}

@description('Node taints for pod scheduling')
param nodeTaints array = []

@description('The resource ID of the subnet')
param vnetSubnetId string

@description('Enable auto-scaling')
param enableAutoScaling bool = true

@description('The Kubernetes version')
param kubernetesVersion string = ''

@description('OS Disk Size in GB')
@minValue(30)
@maxValue(1024)
param osDiskSizeGB int = 30

@description('OS Disk Type')
@allowed([
  'Managed'
  'Ephemeral'
])
param osDiskType string = 'Managed'

@description('The maximum number of pods per node')
@minValue(10)
@maxValue(250)
param maxPods int = 30

@description('The mode of the node pool')
@allowed([
  'System'
  'User'
])
param mode string = 'User'

@description('The priority of the node pool')
@allowed([
  'Regular'
  'Spot'
])
param priority string = 'Regular'

@description('The eviction policy for Spot instances')
@allowed([
  'Delete'
  'Deallocate'
])
param evictionPolicy string = 'Delete'

@description('The maximum price for Spot instances (-1 for on-demand price)')
param spotMaxPrice int = -1

@description('Resource tags')
param tags object = {}

// Reference to existing AKS cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: clusterName
}

// User node pool resource
resource nodePool 'Microsoft.ContainerService/managedClusters/agentPools@2024-05-01' = {
  name: name
  parent: aksCluster
  properties: {
    count: nodeCount
    vmSize: vmSize
    osDiskSizeGB: osDiskSizeGB
    osDiskType: osDiskType
    vnetSubnetID: vnetSubnetId
    maxPods: maxPods
    type: 'VirtualMachineScaleSets'
    mode: mode
    orchestratorVersion: !empty(kubernetesVersion) ? kubernetesVersion : null

    // Auto-scaling configuration
    enableAutoScaling: enableAutoScaling
    minCount: enableAutoScaling ? minCount : null
    maxCount: enableAutoScaling ? maxCount : null

    // Node labels and taints
    nodeLabels: nodeLabels
    nodeTaints: nodeTaints

    // Spot instance configuration
    scaleSetPriority: priority
    scaleSetEvictionPolicy: priority == 'Spot' ? evictionPolicy : null
    spotMaxPrice: priority == 'Spot' ? spotMaxPrice : null

    // Other configurations
    tags: tags
  }
}

// Outputs
output id string = nodePool.id
output name string = nodePool.name
output provisioningState string = nodePool.properties.provisioningState
