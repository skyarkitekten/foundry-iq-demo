// Azure Key Vault for AI Foundry Hub secret management
@description('Name of the Key Vault')
param keyVaultName string

@description('Location for the Key Vault')
param location string = resourceGroup().location

@description('Tags for the Key Vault')
param tags object = {}

@description('Object IDs of principals that should have Key Vault Secrets Officer access (e.g. Foundry Hub managed identity)')
param secretsOfficerObjectIds array = []

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Grant Key Vault Secrets Officer to each specified principal
// Role: Key Vault Secrets Officer (b86a8fe4-44ce-4948-aee5-eccb2c155cd7)
resource secretsOfficerAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for objectId in secretsOfficerObjectIds: {
  name: guid(keyVault.id, objectId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: objectId
    principalType: 'ServicePrincipal'
  }
}]

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
