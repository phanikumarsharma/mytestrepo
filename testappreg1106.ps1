Param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $subscriptionid,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $Username,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $Password,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $WebApp,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $redirectURL
)

#Initialize
$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"
$homePage = "$newReplyUrl"
$identifierUri = $redirectURL
$spnRole = "contributor"

#Initialize subscription
$isAzureModulePresent = Get-Module -Name AzureRM* -ListAvailable
if ([String]::IsNullOrEmpty($isAzureModulePresent) -eq $true)
{
    Write-Output "Script requires AzureRM modules. Obtain from https://github.com/Azure/azure-powershell/releases." -Verbose
    return
}

Import-Module -Name AzureRM.Profile
Write-Output "Provide your credentials to access Azure subscription $subscriptionId" -Verbose
$securedPassword = ConvertTo-SecureString $Password -AsPlainText -Force
#Create a Credentials Object
$credentials = New-Object System.Management.Automation.PSCredential ($Username, $securedPassword)
# Authenticate to Azure

Login-AzureRmAccount -SubscriptionId $subscriptionId -Credential $credentials
$azureSubscription = Get-AzureRmSubscription -SubscriptionId $subscriptionId
$connectionName = $azureSubscription.SubscriptionName

#Check if AD Application Identifier URI is unique
Write-Output "Verifying App URI is unique ($identifierUri)" -Verbose
$existingApplication = Get-AzureRmADApplication -IdentifierUri $identifierUri
if ($existingApplication -ne $null) {
    $appId = $existingApplication.ApplicationId
    Write-Output "An AAD Application already exists with App URI $identifierUri (Application Id: $appId). Choose a different app display name"  -Verbose
    return
}

$startDate = Get-Date
$endDate = $startDate.AddYears($script:yearsOfExpiration)
#$aadAppKeyPwd = New-AzureADApplicationPasswordCredential -ObjectId $myApp.ObjectId -CustomKeyIdentifier "Primary" -StartDate $startDate -EndDate $endDate
$Guid = New-Guid
$PasswordCredential = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordCredential
$PasswordCredential.StartDate = $startDate
$PasswordCredential.EndDate = $startDate.AddYears(1)
$PasswordCredential.KeyId = $Guid
$PasswordCredential.Value = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Guid))))+"="
$appPassword=$PasswordCredential.Value

#Create a new AD Application
Write-Output "Creating a new Application in AAD (App URI - $identifierUri)" -Verbose
$secureAppPassword = $appPassword | ConvertTo-SecureString -AsPlainText -Force
$azureAdApplication = New-AzureRmADApplication -DisplayName $WebApp -HomePage $homePage -IdentifierUris $identifierUri -Password $secureAppPassword -Verbose
$appId = $azureAdApplication.ApplicationId
Write-Output "Azure AAD Application creation completed successfully (Application Id: $appId)" -Verbose

#Create new SPN
Write-Output "Creating a new SPN" -Verbose
$spn = New-AzureRmADServicePrincipal -ApplicationId $appId
$spnName = $spn.ServicePrincipalNames
Write-Output "SPN creation completed successfully (SPN Name: $spnName)" -Verbose

#Assign role to SPN
Write-Output "Waiting for SPN creation to reflect in Directory before Role assignment"
Start-Sleep 20
Write-Output "Assigning role ($spnRole) to SPN App ($appId)" -Verbose
New-AzureRmRoleAssignment -RoleDefinitionName $spnRole -ServicePrincipalName $appId
Write-Output "SPN role assignment completed successfully" -Verbose

#Print the values
Write-Output "`nCopy and Paste below values for Service Connection" -Verbose
Write-Output "Service Principal Id: $appId"
Write-Output "Service Principal Key: $appPassword"

