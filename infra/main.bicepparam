using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'sample')
param location = readEnvironmentVariable('AZURE_LOCATION', 'japaneast')

// Resource naming parameters
param resourceGroupPrefix = 'rg-aks-scale-to-zero'
param clusterNamePrefix = 'aks-scale-to-zero'
param logAnalyticsNamePrefix = 'log-aks-scale-to-zero'
param acrNamePrefix = 'craksscaletozero'
param keyVaultNamePrefix = 'kv-aks-s2z'

// AKS configuration
param kubernetesVersion = '1.32'

// Resource tags
param tags = {
  Environment: environmentName
  Project: 'AKS Scale to Zero'
  ManagedBy: 'Bicep'
}
