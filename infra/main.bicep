targetScope = 'subscription'

param projectName string

param location string = deployment().location

param gitAccountName string
param gitCollaborationBranch string = 'main'
param gitRepositoryName string
param gitRootFolder string

var environments = ['dev', 'tst','prd']

module env 'environment.bicep' = [for environment in environments: {
  name: 'env-${environment}'
  params: {
    projectName: projectName
    environment: environment
    location: location
    gitAccountName: gitAccountName
    gitCollaborationBranch: gitCollaborationBranch
    gitRepositoryName: gitRepositoryName
    gitRootFolder: gitRootFolder
  }
}]


