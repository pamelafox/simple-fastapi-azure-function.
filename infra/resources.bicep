param location string = resourceGroup().location
param resourceToken string
param tags object

var functionServiceName = '${resourceToken}-function-app'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: '${resourceToken}-logworkspace'
  location: location
  tags: tags
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: '${resourceToken}-appinsights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: '${resourceToken}storage'
  location: location
  kind: 'StorageV2'
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }

  resource blobServices 'blobServices' = {
    name: 'default'
    resource container 'containers' = {
      name: functionServiceName
    }
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${resourceToken}-plan'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

module functionApp 'core/host/functions-flex.bicep' = {
  name: 'function-app'
  params: {
    name: functionServiceName
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    alwaysOn: false
    appSettings: {
      FUNCTIONS_EXTENSION_VERSION: '~4'
      AzureWebJobsStorage__accountName: storageAccount.name
    }
    appServicePlanId: hostingPlan.id
    runtimeName: 'python'
    runtimeVersion: '3.11'
    storageAccountName: storageAccount.name
    applicationInsightsName: appInsights.name
  }
}


module diagnostics 'app-diagnostics.bicep' = {
  name: 'function-diagnostics'
  params: {
    appName: functionApp.outputs.name
    kind: 'functionapp'
    diagnosticWorkspaceId: logAnalytics.id
  }
}


module apiManagementResources 'apimanagement.bicep' = {
  name: 'apimanagement-resources'
  params: {
    prefix: resourceToken
    location: location
    tags: tags
    functionAppName: functionApp.outputs.name
    appInsightsName: appInsights.name
    appInsightsId: appInsights.id
    appInsightsKey: appInsights.properties.InstrumentationKey
  }
}

module apimFunctionConnection 'apim-function.bicep' = {
  name: 'apim-function'
  params: {
    functionAppName: functionApp.outputs.name
    apiManagementConfigId: '${apiManagementResources.outputs.apimServiceID}/apis/model-prediction-api'
  }
}


output apimServiceUrl string = apiManagementResources.outputs.apimServiceUrl
output functionUrl string = functionApp.outputs.uri
