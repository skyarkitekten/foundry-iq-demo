// Azure AI Foundry Hub and Project
@description('Name of the AI Foundry hub')
param hubName string

@description('Name of the AI Foundry project')
param projectName string

@description('Location for AI Foundry resources')
param location string = resourceGroup().location

@description('Tags for AI Foundry resources')
param tags object = {}

@description('OpenAI service endpoint URL (e.g. https://<name>.openai.azure.com/)')
param openAIEndpoint string

@description('Azure AI Search endpoint URL (e.g. https://<name>.search.windows.net)')
param searchEndpoint string

@description('Storage account resource ID to connect')
param storageAccountId string

// Create AI Hub (AI Studio workspace)
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: hubName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'Hub'
  properties: {
    description: 'Azure AI Foundry Hub for Knowledge Retrieval Demo'
    friendlyName: hubName
    storageAccount: storageAccountId
    publicNetworkAccess: 'Enabled'
  }
}

// Create AI Project under the hub
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'Project'
  properties: {
    description: 'Azure AI Foundry Project for Agentic RAG'
    friendlyName: projectName
    hubResourceId: aiHub.id
    publicNetworkAccess: 'Enabled'
  }
}

// Create connection to OpenAI
resource openAIConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: aiProject
  name: 'openai-connection'
  properties: {
    category: 'AzureOpenAI'
    target: openAIEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
    }
  }
}

// Create connection to AI Search
resource searchConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: aiProject
  name: 'search-connection'
  properties: {
    category: 'CognitiveSearch'
    target: searchEndpoint
    authType: 'AAD'
    isSharedToAll: true
  }
}

// Output Foundry details
output hubId string = aiHub.id
output hubName string = aiHub.name
output projectId string = aiProject.id
output projectName string = aiProject.name
output projectEndpoint string = 'https://${aiProject.name}.${location}.api.azureml.ms'
output hubPrincipalId string = aiHub.identity.principalId
output projectPrincipalId string = aiProject.identity.principalId
