// Azure AI Search Service
@description('Name of the Azure AI Search service')
param searchServiceName string

@description('Location for the search service')
param location string = resourceGroup().location

@description('SKU for the search service')
@allowed([
  'basic'
  'standard'
  'standard2'
  'standard3'
  'storage_optimized_l1'
  'storage_optimized_l2'
])
param sku string = 'basic'

@description('Tags for the search service')
param tags object = {}

resource searchService 'Microsoft.Search/searchServices@2024-07-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    hostingMode: 'default'
    partitionCount: 1
    replicaCount: 1
    publicNetworkAccess: 'enabled'
    semanticSearch: 'free'
  }
}

// Output the search service details
// NOTE: Admin key intentionally not output here — retrieve post-deployment via:
//   az search admin-key show --service-name <name> -g <rg> --query primaryKey
output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'
