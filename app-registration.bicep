param appName string
param subscriptionId string

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'CreateAppRegistrationScript'
  location: resourceGroup().location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.30.0'
    timeout: 'PT30M'
    retentionInterval: 'P1D'
    scriptContent: '''
      #!/bin/bash
      echo "Creating App Registration: $appName"

      # Create the App Registration
      APP_ID=$(az ad app create --display-name "$appName" --query appId -o tsv)
      echo "App Registration created with ID: $APP_ID"

      # Get Object ID
      OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)
      echo "Object ID: $OBJECT_ID"

      # Generate a Secret with 2-Year Expiry
      SECRET_END_DATE=$(date -d "+2 years" --utc +"%Y-%m-%dT%H:%M:%SZ")
      SECRET_VALUE=$(az ad app credential reset --id $APP_ID --display-name "Secret" --end-date "$SECRET_END_DATE" --query password -o tsv)
      echo "Secret Expiry Date: $SECRET_END_DATE"

      # Create Service Principal
      SP_ID=$(az ad sp create --id $APP_ID --query id -o tsv)
      echo "Service Principal created with ID: $SP_ID"

      # Application Permissions
      GRAPH_PERMISSIONS=("bf394140-e372-4bf9-a898-299cfc7564e5")
      DEFENDER_PERMISSIONS=(
          "02b005dd-f804-43b4-8fc7-078460413f74"
          "227f2ea0-c2c2-4428-b7af-9ff40f1a720e"
          "37f71c98-d198-41ae-964d-2c49aab74926"
          "41269fc5-d04d-4bfd-bce7-43a51cea049a"
          "47bf842d-354b-49ef-b741-3a6dd815bc13"
          "528ca142-c849-4a5b-935e-10b8b9c38a84"
          "6443965c-7dd2-4cfd-b38f-bb7772bee163"
          "6a33eedf-ba73-4e5a-821b-f057ef63853a"
          "71fe6b80-7034-4028-9ed8-0f316df9c3ff"
          "721af526-ffa8-42d7-9b84-1a56244dd99d"
          "8788f1a9-beca-4e26-ba58-10513f3b896f"
          "93489bf5-0fbc-4f2d-b901-33f2fe08ff05"
          "a833834a-4cf1-4732-8acf-bbcfa13fb610"
          "e870c0c1-c1a2-41ca-948e-a33912d2d3f0"
          "ea8291d3-4b9a-44b5-bc3a-6cea3026dc79"
      )

      for PERMISSION in "${GRAPH_PERMISSIONS[@]}"; do
          az ad app permission add --id $APP_ID --api 00000003-0000-0000-c000-000000000000 --api-permissions $PERMISSION=Role
          echo "Assigned Graph permission: $PERMISSION"
      done

      for PERMISSION in "${DEFENDER_PERMISSIONS[@]}"; do
          az ad app permission add --id $APP_ID --api fc780465-2017-40d4-a0c5-307022471b92 --api-permissions $PERMISSION=Role
          echo "Assigned Defender permission: $PERMISSION"
      done

      # Assign Microsoft Sentinel Reader Role at Subscription Level
      az role assignment create --assignee $SP_ID --role "Microsoft Sentinel Reader" --scope "/subscriptions/$subscriptionId"
      echo "Assigned Sentinel Reader role"

      echo -e "\n=== OUTPUT DETAILS ==="
      echo "Client ID: $APP_ID"
      echo "Object ID: $OBJECT_ID"
      echo "Tenant ID: $(az account show --query tenantId -o tsv)"
      echo "Secret Value: $SECRET_VALUE"
      echo "Secret Expiry Date: $SECRET_END_DATE"
    '''
    environmentVariables: [
      {
        name: 'appName'
        value: appName
      },
      {
        name: 'subscriptionId'
        value: subscriptionId
      }
    ]
    forceUpdateTag: uniqueString(resourceGroup().id)
    cleanupPreference: 'OnSuccess'
  }
}
