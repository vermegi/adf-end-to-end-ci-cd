targetScope = 'subscription'

param projectName string

@allowed([
  'dev'
  'tst'
  'prd'
])
param environment string = 'dev'

param location string

param gitAccountName string
param gitCollaborationBranch string
param gitRepositoryName string
param gitRootFolder string

var basename = '${projectName}-${environment}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${basename}'
  location: location
}

module adf 'adf.bicep' = {
  name: 'adf-${environment}'
  scope: resourceGroup
  params: {
    name: basename
    gitAccountName: gitAccountName
    gitCollaborationBranch: gitCollaborationBranch
    gitRepositoryName: gitRepositoryName
    gitRootFolder: gitRootFolder
    environment: environment
    location: resourceGroup.location
  }
}


