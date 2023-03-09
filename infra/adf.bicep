param name string

param location string

param environment string = 'dev'

param gitAccountName string
param gitCollaborationBranch string
param gitRepositoryName string
param gitRootFolder string

var repoConfiguration =  {
  accountName: gitAccountName
  collaborationBranch: gitCollaborationBranch
  repositoryName: gitRepositoryName
  rootFolder: gitRootFolder
  type: 'FactoryGitHubConfiguration'
}

resource symbolicname 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: '${name}-adf'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    globalParameters: {}
    // only configire git integration for dev environment
    repoConfiguration: environment == 'dev' ? repoConfiguration : null
  }
}
