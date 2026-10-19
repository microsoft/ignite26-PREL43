// VectorSense Labs - Scoring Engine: Azure infrastructure for one tenant/subscription.
// Deploys: VNet, AKS (workload identity, Key Vault CSI, app routing), PostgreSQL Flexible Server (private),
// Key Vault (RBAC), Container Registry, Log Analytics, and the user-assigned identity the app runs as.
//
// Normally run through deploy/scripts/deploy.sh, which builds the parameters from deploy/env/<tenant>.env.
targetScope = 'resourceGroup'

@description('Short environment token used in names, e.g. test, prod.')
param env string = 'prod'

@description('Workload prefix for resource names.')
param prefix string = 'vsl'

param location string = resourceGroup().location

@description('Kubernetes namespace and service account the app runs under (must match the Helm release).')
param k8sNamespace string = 'vectorsense'
param k8sServiceAccount string = 'vectorsense-scoring'

@description('AKS system node pool size and VM SKU.')
param aksNodeCount int = 3
param aksMaxNodeCount int = 8
param aksVmSize string = 'Standard_D4ds_v5'
param kubernetesVersion string = '1.31'

@description('PostgreSQL compute + storage.')
param pgSku string = 'Standard_D2ds_v5'
param pgTier string = 'GeneralPurpose'
param pgStorageGb int = 128
param pgHighAvailability bool = false

@description('Admin principal (user or group object ID) granted Key Vault Secrets Officer and AKS admin.')
param adminPrincipalId string

@secure()
param pgAdminPassword string = '${toUpper(substring(newGuid(), 0, 8))}!${newGuid()}'
@secure()
param jwtSigningKey string = '${newGuid()}${newGuid()}'
@secure()
param secretPepper string = newGuid()
@secure()
@description('Break-glass local admin password (only used if the portal runs with authMode=local).')
param localAdminPassword string = '${newGuid()}Aa1!'

var suffix = take(uniqueString(resourceGroup().id), 5)
var names = {
  law: '${prefix}-${env}-law'
  vnet: '${prefix}-${env}-vnet'
  aks: '${prefix}-${env}-aks'
  pg: '${prefix}-${env}-pg-${suffix}'
  kv: take('${prefix}-${env}-kv-${suffix}', 24)
  acr: take(replace('${prefix}${env}acr${suffix}', '-', ''), 50)
  uami: '${prefix}-${env}-id-scoring'
}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: names.law
  location: location
  properties: { sku: { name: 'PerGB2018' }, retentionInDays: 30 }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: names.vnet
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.40.0.0/16'] }
    subnets: [
      { name: 'snet-aks', properties: { addressPrefix: '10.40.0.0/20' } }
      {
        name: 'snet-pg'
        properties: {
          addressPrefix: '10.40.16.0/24'
          delegations: [{ name: 'pg', properties: { serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers' } }]
        }
      }
    ]
  }
}

resource pgDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${names.pg}.private.postgres.database.azure.com'
  location: 'global'
}

resource pgDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: pgDns
  name: 'vnet-link'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: names.pg
  location: location
  sku: { name: pgSku, tier: pgTier }
  properties: {
    version: '16'
    administratorLogin: 'scoringadmin'
    administratorLoginPassword: pgAdminPassword
    storage: { storageSizeGB: pgStorageGb, autoGrow: 'Enabled' }
    backup: { backupRetentionDays: 14, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: pgHighAvailability ? 'ZoneRedundant' : 'Disabled' }
    network: {
      delegatedSubnetResourceId: '${vnet.id}/subnets/snet-pg'
      privateDnsZoneArmResourceId: pgDns.id
      publicNetworkAccess: 'Disabled'
    }
  }
  dependsOn: [pgDnsLink]
}

resource pgDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: 'scoring'
  properties: { charset: 'UTF8', collation: 'en_US.utf8' }
}

resource pgMaxConn 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pg
  name: 'max_connections'
  properties: { value: '400', source: 'user-override' }
  dependsOn: [pgDb]
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.uami
  location: location
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: names.acr
  location: location
  sku: { name: 'Standard' }
  properties: { adminUserEnabled: false }
}

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: names.aks
  location: location
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Base', tier: 'Standard' }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: names.aks
    enableRBAC: true
    disableLocalAccounts: false
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: aksNodeCount
        minCount: aksNodeCount
        maxCount: aksMaxNodeCount
        enableAutoScaling: true
        vmSize: aksVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        availabilityZones: ['1', '2', '3']
        vnetSubnetID: '${vnet.id}/subnets/snet-aks'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.41.0.0/16'
      dnsServiceIP: '10.41.0.10'
    }
    oidcIssuerProfile: { enabled: true }
    securityProfile: { workloadIdentity: { enabled: true } }
    ingressProfile: { webAppRouting: { enabled: true } }
    addonProfiles: {
      azureKeyvaultSecretsProvider: { enabled: true, config: { enableSecretRotation: 'true', rotationPollInterval: '5m' } }
      omsagent: { enabled: true, config: { logAnalyticsWorkspaceResourceID: law.id } }
    }
    autoUpgradeProfile: { upgradeChannel: 'patch' }
  }
}

resource fic 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uami
  name: 'aks-${k8sNamespace}-${k8sServiceAccount}'
  properties: {
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sServiceAccount}'
    audiences: ['api://AzureADTokenExchange']
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: names.kv
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
  }
}

var staticSecrets = {
  'pg-admin-password': pgAdminPassword
  'jwt-signing-key': jwtSigningKey
  'secret-pepper': secretPepper
  'admin-password': localAdminPassword
}

resource kvSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for s in items(staticSecrets): {
  parent: kv
  name: s.key
  properties: { value: s.value }
}]

resource kvDatabaseUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'database-url'
  properties: {
    value: 'postgresql+asyncpg://scoringadmin:${uriComponent(pgAdminPassword)}@${pg.properties.fullyQualifiedDomainName}:5432/scoring?ssl=require'
  }
}

// ---- role assignments ----
var roles = {
  kvSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  kvSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  aksClusterAdmin: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
}

resource uamiKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, uami.id, roles.kvSecretsUser)
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.kvSecretsUser)
  }
}

resource adminKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, adminPrincipalId, roles.kvSecretsOfficer)
  properties: {
    principalId: adminPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.kvSecretsOfficer)
  }
}

resource kubeletAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, aks.id, roles.acrPull)
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
  }
}

resource adminAks 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aks
  name: guid(aks.id, adminPrincipalId, roles.aksClusterAdmin)
  properties: {
    principalId: adminPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.aksClusterAdmin)
  }
}

output aksName string = aks.name
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = kv.name
output workloadIdentityClientId string = uami.properties.clientId
output workloadIdentityPrincipalId string = uami.properties.principalId
output tenantId string = subscription().tenantId
output postgresFqdn string = pg.properties.fullyQualifiedDomainName
output k8sNamespace string = k8sNamespace
