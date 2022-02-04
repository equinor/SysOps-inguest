# For more info check https://github.com/equinor/SysOps/tree/main/in-guest-policy
# Fill in all parameters
$Subscription = Get-AzSubscription -SubscriptionName 'Q901-platform-dev'
$ResourceGroup = Get-AzResourceGroup -Name 'rg-ovea'
$Location = "westeurope"
$ZipName = "InstallLAPSv2"
$ContentURIMSI = "https://github.com/equinor/SysOps-inguest/raw/master/InstallMSI/$ZipName/$ZipName.zip"
$PolicyId = "VM-Guest-Policy-LAPSv2"
$PolicyDisplayName = "VM Guest Policy LAPS Deploy v2"
$PolicyDescription = "This Policy deploys Local Administrator Password Solution (LAPS) on the Server v2"

# Generates localhost.mof in InstallMSI folder
Configuration InstallMSI {
    Import-DscResource -ModuleName 'psdscresources'
    Node localhost
    {
        MsiPackage LAPS
        {
            ProductId = '{97E2CA7B-B657-4FF7-A6DB-30ECC73E1E28}'
            Path = 'https://download.microsoft.com/download/C/7/A/C7AAD914-A8A6-4904-88A1-29E657445D03/LAPS.x64.msi'
            Ensure = 'Present'
        }
    }
}
InstallMSI

# Create zip file in InstallMSI folder
New-GuestConfigurationPackage `
  -Name $ZipName `
  -Path 'InstallMSI' `
  -Configuration 'InstallMSI\localhost.mof' `
  -Type AuditAndSet `
  -Force

# For the next step make sure newest zip is available in repo and update $ContentURIMSI
# Create policy locally
New-GuestConfigurationPolicy `
  -PolicyId $PolicyId `
  -ContentUri $ContentURIMSI `
  -DisplayName $PolicyDisplayName `
  -Description $PolicyDescription `
  -Path 'InstallMSI\policy' `
  -Platform 'Windows' `
  -Version 1.0.0 `
  -Mode 'ApplyAndAutoCorrect' `
  -Verbose

# Publish policy defenition to Azure
New-AzPolicyDefinition `
    -Name $PolicyId `
    -Policy 'InstallMSI\policy\DeployIfNotExists.json' `
    -SubscriptionId $($Subscription.Id)

# Assign policy to Resource Group
$Policy = Get-AzPolicyDefinition -Name $PolicyId
New-AzPolicyAssignment `
    -Name $PolicyId `
    -PolicyDefinition $Policy `
    -Scope $ResourceGroup.ResourceId `
    -IdentityType 'SystemAssigned' `
    -Location $Location

# Assign role to resourcegroup (This step is not needed if assign policy is done in portal)
$SpObject = Get-AzADServicePrincipal -DisplayName $PolicyId
# Reason for sleep. It failed during one of our tests. SpObject was not set.
Start-Sleep -Seconds 1
New-AzRoleAssignment `
    -ObjectId $SpObject.Id `
    -Scope $ResourceGroup.ResourceId `
    -RoleDefinitionName 'Contributor'

# Clean up
Remove-Item -Path '.\InstallMSI\localhost.mof' -Force
Remove-Item -Path '.\InstallMSI\policy' -Recurse -Force
Remove-Item -Path ".\InstallMSI\$ZipName\unzippedPackage" -Recurse -Force

# Remove Policy assignment
Remove-AzPolicyAssignment -Scope $ResourceGroup.ResourceId -Name $Policyid

# Remove Policy definition
Remove-AzPolicyDefinition -Name $PolicyId -Force