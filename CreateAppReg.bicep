targetScope = 'subscription'

@description('Name for the new app registration. Defaults to "ArgoSecureAccess".')
param appName string = 'ArgoSecureAccess'

@description('Azure region for resources (used for the Managed Identity and script).')
param location string = 'eastus'

@description('Resource Group name to hold the managed identity. Will be created if not existing.')
param identityRgName string = 'ArgoSecureAccess-resources'

// Create a resource group to contain the user-assigned Managed Identity
resource identityRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: identityRgName
  location: location
}

// Create a User-Assigned Managed Identity in the above resource group
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  scope: identityRg
  name: '${appName}-identity'
  location: location
}

// Grant the Managed Identity Contributor role at the subscription level (required for script to create resources)
resource assignContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: subscription()  // subscription-scope role assignment
  name: guid(subscription().id, scriptIdentity.properties.principalId, 'sub-contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId(
       'Microsoft.Authorization/roleDefinitions', 
       'b24988ac-6180-42a0-ab88-20f7382dd24c'  // Contributor role ID
    )
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployment script to create the App Registration, Service Principal, API permission, and secret
resource appSetupScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'appRegistrationScript'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      // Use the managed identity defined above for script execution
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.42.0'            // Azure CLI version for the script container
    timeout: 'PT10M'                 // 10 minute timeout for script
    cleanupPreference: 'OnSuccess'   // auto-remove script container on success
    retentionInterval: 'P1D'         // keep logs up to 1 day (for troubleshooting if needed)
    forceUpdateTag: utcNow()         // ensures script runs on each deployment (timestamp as unique tag)
    scriptContent: '''
      #!/bin/bash
      set -e  # stop on error
      APP_NAME="${1:-ArgoSecureAccess}"
      SUB_ID="${2}"
      echo "Logging in with managed identity..."
      az login --identity -u ${scriptIdentity.properties.clientId} --allow-no-subscriptions > /dev/null
      az account set --subscription "$SUB_ID"
      echo "Creating app registration: $APP_NAME"
      APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
      echo "App created with Application ID: $APP_ID"
      echo "Creating service principal for the app..."
      az ad sp create --id "$APP_ID" --only-show-errors
      echo "Assigning API permission (Microsoft Graph User.Read)..."
      az ad app permission add --id "$APP_ID" \ 
         --api 00000003-0000-0000-c000-000000000000 \ 
         --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope
      echo "Creating client secret for the app..."
      CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --append --query password -o tsv)
      TENANT_ID=$(az account show --query tenantId -o tsv)
      echo "Writing outputs..."
      # Output JSON with the required values to the expected path
      jq -n --arg tenant "$TENANT_ID" \
            --arg sub "$SUB_ID" \
            --arg app "$APP_ID" \
            --arg secret "$CLIENT_SECRET" \
            '{ tenantId: $tenant, subscriptionId: $sub, applicationId: $app, clientSecret: $secret }' \
         > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    arguments: '''${appName} ${subscription().subscriptionId}'''  // pass appName and subscriptionId into the script
  }
  dependsOn: [
    assignContributor  // ensure role is assigned before script runs
  ]
}

// Outputs returned from the deployment
output tenantId string       = appSetupScript.properties.outputs.tenantId
output subscriptionId string = appSetupScript.properties.outputs.subscriptionId
output applicationId string  = appSetupScript.properties.outputs.applicationId
output clientSecret string   = appSetupScript.properties.outputs.clientSecret
