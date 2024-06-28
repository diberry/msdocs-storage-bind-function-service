targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param resourceGroupName string = ''
param apiServiceName string = 'api'
param appServicePlanName string = ''
param storageAccountName string = ''
param computerVisionAccountName string = ''
param cosmosDbAccountName string = ''

param blobContainerName string = 'files'

// Id of the user or app to assign application roles
param principalId string = ''

// Differentiates between automated and manual deployments
param isContinuousDeployment bool // Set in main.parameters.json

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var storageUrl = 'https://${storage.outputs.name}.blob.${environment().suffixes.storage}'

// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// The application backend API
module api './core/host/functions.bicep' = {
  name: 'api'
  scope: resourceGroup
  params: {
    name: '${abbrs.webSitesFunctions}api-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': apiServiceName })
    allowedOrigins: ['*']
    alwaysOn: false
    runtimeName: 'node'
    runtimeVersion: '20'
    appServicePlanId: appServicePlan.outputs.id
    storageAccountName: storage.outputs.name
    managedIdentity: true
    appSettings: {
      AZURE_STORAGE_URL: storageUrl
      AZURE_STORAGE_CONTAINER_NAME: blobContainerName
     }
  }
}

// Compute plan for the Azure Functions API
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: resourceGroup
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'Y1'
      tier: 'Dynamic'
    }
  }
}

// Storage for Azure Functions API and Blob storage
module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: resourceGroup
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    allowBlobPublicAccess: false
    containers: [
      {
        name: blobContainerName
        publicAccess: 'None'
      }
    ]
  }
}

// Computer Vision
module ocr './core/ai/cognitiveservices.bicep' = {
  name: 'computervision'
  scope: resourceGroup
  params: {
    cognitiveServiceName: !empty(computerVisionAccountName) ? computerVisionAccountName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: location
  }
}

// Cosmos DB
module database 'core/database/database.bicep' = {
  name: 'database'
  scope: resourceGroup
  params: {
    accountName:  !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: location
    tags: tags
  }
}

// Managed identity roles assignation
// ---------------------------------------------------------------------------
module dbCustomRoleDefinition 'core/database/cosmos-db/nosql/rbac-definition.bicep' = {
  scope: resourceGroup
  name: 'cosmos-sql-role-definition'
  params: {
    accountName: database.name
  }
  dependsOn: [
    database
  ]
}

// User roles - local developer
module storageRoleUser 'core/security/role.bicep' = if (!isContinuousDeployment) {
  scope: resourceGroup
  name: 'storage-contrib-role-user'
  params: {
    principalId: principalId
    // Storage Blob Data Contributor
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalType: 'User'
  }
}
module computerVisionRoleUser 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'computervision-role-user'
  params: {
    principalId: api.outputs.identityPrincipalId
    // Cognitive Services Contributor
    roleDefinitionId: '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'
    principalType: 'User'
  }
}
// module userRoleCosmosDb 'core/database/cosmos-db/nosql/rbac-assignment.bicep' = {
//   scope: resourceGroup
//   name: 'cosmos-sql-user-role'
//   params: {
//     accountName: database.name
//     roleDefinitionId: dbCustomRoleDefinition.outputs.id
//     principalId: principalId
//   }
// }

// System roles - production deployment
module storageRoleApi 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'storage-role-api'
  params: {
    principalId: api.outputs.identityPrincipalId
    // Storage Blob Data Contributor
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalType: 'ServicePrincipal'
  }
}

module computerVisionRoleApi 'core/security/role.bicep' = {
  scope: resourceGroup
  name: 'computervision-role-api'
  params: {
    principalId: api.outputs.identityPrincipalId
    // Cognitive Services Contributor
    roleDefinitionId: '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'
    principalType: 'ServicePrincipal'
  }
}
// module cosmosDbRoleApi 'core/database/cosmos-db/nosql/rbac-assignment.bicep' = {
//   scope: resourceGroup
//   name: 'cosmos-nosql-role=api'
//   params: {
//     accountName: database.name
//     roleDefinitionId: dbCustomRoleDefinition.outputs.id
//     principalId: api.outputs.identityPrincipalId
//   }
// }

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroup.name

output AZURE_STORAGE_URL string = storageUrl
output AZURE_STORAGE_CONTAINER_NAME string = blobContainerName

output API_URL string = api.outputs.uri
