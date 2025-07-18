@description('Name of the Log Analytics workspace')
param name string

@description('Location for the Log Analytics workspace')
param location string

@description('Tags to be applied to the Log Analytics workspace')
param tags object = {}

@description('The workspace data retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('The SKU of the workspace')
@allowed([
  'PerGB2018'
  'CapacityReservation'
])
param sku string = 'PerGB2018'

// Create Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1 // No daily cap
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Outputs
output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
