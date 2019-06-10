param(

    [Parameter(Mandatory = $True)]
    $AzureLoginId,

    [Parameter(Mandatory = $True)]
    $AzureLoginPassword,

    [Parameter(Mandatory = $True)]
    $ApplicationDisplayName,

    [Parameter(Mandatory = $True)]
    $IdentifierUri,

    [Parameter(Mandatory = $True)]
    $HomePageUrl
)

$securedPassword = ConvertTo-SecureString $AzureLoginPassword -AsPlainText -Force
#Create a Credentials Object
$credentials = New-Object System.Management.Automation.PSCredential ($AzureLoginId, $securedPassword)
# Authenticate to Azure
Connect-AzureAD -Credential $credentials

# Check the app registration exist/ not using the application display name
if(!($myApp = Get-AzureADApplication -Filter "DisplayName eq '$($ApplicationDisplayName)'" -ErrorAction SilentlyContinue))
{

    # Create a new app registration
    $myApp = New-AzureADApplication -DisplayName $ApplicationDisplayName -IdentifierUris $IdentifierUri
}
$ReplyURLs = @($IdentifierUri, $HomePageUrl)
$startDate = Get-Date
$endDate = $startDate.AddYears($script:yearsOfExpiration)
$aadAppKeyPwd = New-AzureADApplicationPasswordCredential -ObjectId $myApp.ObjectId -CustomKeyIdentifier "Primary" -StartDate $startDate -EndDate $endDate
$Guid = New-Guid
$startDate = Get-Date
$PasswordCredential = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordCredential
$PasswordCredential.StartDate = $startDate
$PasswordCredential.EndDate = $startDate.AddYears(1)
$PasswordCredential.KeyId = $Guid
$PasswordCredential.Value = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Guid))))+"="

Write-Host "Client Id is:" $myApp.AppId
Write-Host "Client Secret is:" $PasswordCredential.Value