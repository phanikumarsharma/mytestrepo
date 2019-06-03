$subscriptionid = Get-AutomationVariable -Name 'subscriptionid'
$ResourceGroupName = Get-AutomationVariable -Name 'ResourceGroupName'
$fileURI = Get-AutomationVariable -Name 'fileURI'
$Username = Get-AutomationVariable -Name 'Username'
$Password = Get-AutomationVariable -Name 'Password'
$automationAccountName = Get-AutomationVariable -Name 'accountName'
$WebApp = Get-AutomationVariable -Name 'webApp'

Invoke-WebRequest -Uri $fileURI -OutFile "C:\wvd-monitoring-ux.zip"
New-Item -Path "C:\wvd-monitoring-ux" -ItemType directory -Force -ErrorAction SilentlyContinue
Expand-Archive "C:\wvd-monitoring-ux.zip" -DestinationPath "C:\wvd-monitoring-ux" -ErrorAction SilentlyContinue

$modules="https://raw.githubusercontent.com/Azure/RDS-Templates/wvd-mgmt-ux/wvd-templates/wvd-management-ux/deploy/scripts/msft-wvd-saas-offering.zip"
Invoke-WebRequest -Uri $modules -OutFile "C:\msft-rdmi-saas-offering.zip"
New-Item -Path "C:\msft-rdmi-saas-offering" -ItemType directory -Force -ErrorAction SilentlyContinue
Expand-Archive "C:\msft-rdmi-saas-offering.zip" -DestinationPath "C:\msft-rdmi-saas-offering" -ErrorAction SilentlyContinue
$AzureModulesPath = Get-ChildItem -Path "C:\msft-rdmi-saas-offering\msft-wvd-saas-offering"| Where-Object {$_.FullName -match 'AzureModules.zip'}
Expand-Archive $AzureModulesPath.fullname -DestinationPath 'C:\Modules\Global' -ErrorAction SilentlyContinue


#$AzureModulesPath = Get-ChildItem -Path "C:\wvd-monitoring-ux\wvd-monitoring-ux"| Where-Object {$_.FullName -match 'AzureModules.zip'}
#Expand-Archive $AzureModulesPath.fullname -DestinationPath 'C:\Modules\Global' -ErrorAction SilentlyContinue

Import-Module AzureRM.Resources
Import-Module AzureRM.Profile
Import-Module AzureRM.Websites
Import-Module Azure
Import-Module AzureRM.Automation
Import-Module AzureAD

    Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
    Get-ExecutionPolicy -List
    #The name of the Automation Credential Asset this runbook will use to authenticate to Azure.
    $CredentialAssetName = 'DefaultAzureCredential'

    #Get the credential with the above name from the Automation Asset store
    $Cred = Get-AutomationPSCredential -Name $CredentialAssetName
    Add-AzureRmAccount -Environment 'AzureCloud' -Credential $Cred
    Select-AzureRmSubscription -SubscriptionId $subscriptionid
    #$CodeBitPath= "C:\monitor-ux\monitor-ux"
    $WebAppDirectory = "C:\wvd-monitoring-ux\wvd-monitoring-ux"
    try
    {
    # Get Url of Web-App
    $GetWebApp = Get-AzureRmWebApp -Name $WebApp -ResourceGroupName $ResourceGroupName
    $WebUrl = $GetWebApp.DefaultHostName
                 
    #$requiredAccessName=$ResourceURL.Split("/")[3]
    $redirectURL="https://"+"$WebUrl"+"/"

    Set-Location $WebAppDirectory
    $WebAppExtractedPath = Get-ChildItem -Path $WebAppDirectory| Where-Object {$_.FullName -notmatch '\\*.zip($|\\)'} | Resolve-Path -Verbose

    # Get publishing profile for the web app
    $xml = (Get-AzureRmWebAppPublishingProfile -Name $WebApp -ResourceGroupName $ResourceGroupName -OutputFile null)

    $xml = [xml]$xml

    # Extract connection information from publishing profile
    $username = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userName").value
    $password = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userPWD").value
    $url = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@publishUrl").value

    # Upload files recursively 
    $webclient = New-Object -TypeName System.Net.WebClient
    $webclient.Credentials = New-Object System.Net.NetworkCredential($username,$password)
    $files = Get-ChildItem -Path $WebAppDirectory -Recurse #Removed IsContainer condition
    foreach ($file in $files)
    {
        $relativepath = (Resolve-Path -Path $file.FullName -Relative).Replace(".\", "").Replace('\', '/')  
        $uri = New-Object System.Uri("$url/$relativepath")

        if($file.PSIsContainer)
        {
            $uri.AbsolutePath + "is Directory"
            $ftprequest = [System.Net.FtpWebRequest]::Create($uri);
            $ftprequest.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
            $ftprequest.UseBinary = $true

            $ftprequest.Credentials = New-Object System.Net.NetworkCredential($username,$password)

            $response = $ftprequest.GetResponse();
            $response.StatusDescription
            continue
        }

        "Uploading to " + $uri.AbsoluteUri + " from "+ $file.FullName

        $webclient.UploadFile($uri, $file.FullName)
    } 
    $webclient.Dispose()
    }
    catch [Exception]
    {
        Write-Output $_.Exception.Message
    }



New-PSDrive -Name RemoveAccount -PSProvider FileSystem -Root "C:\" | Out-Null
@"
Param(
    [Parameter(Mandatory=`$True)]
    [string] `$SubscriptionId,
    [Parameter(Mandatory=`$True)]
    [String] `$Username,
    [Parameter(Mandatory=`$True)]
    [string] `$Password,
    [Parameter(Mandatory=`$True)]
    [string] `$ResourceGroupName,
    [Parameter(Mandatory=`$True)]
    [string] `$automationAccountName
 
)
Import-Module AzureRM.profile
Import-Module AzureRM.Automation
`$Securepass=ConvertTo-SecureString -String `$Password -AsPlainText -Force
`$Azurecred=New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList(`$Username, `$Securepass)
`$login=Login-AzureRmAccount -Credential `$Azurecred -SubscriptionId `$SubscriptionId
Remove-AzureRmAutomationAccount -Name `$automationAccountName -ResourceGroupName `$ResourceGroupName -Force 
"@| Out-File -FilePath RemoveAccount:\RemoveAccount.ps1 -Force

    $runbookName='removewvdsaasacctbook'
    #Create a Run Book
    New-AzureRmAutomationRunbook -Name $runbookName -Type PowerShell -ResourceGroupName $ResourceGroupName -AutomationAccountName $automationAccountName

    #Import modules to Automation Account
    $modules="AzureRM.profile,Azurerm.compute,azurerm.resources"
    $modulenames=$modules.Split(",")
    foreach($modulename in $modulenames){
    Set-AzureRmAutomationModule -Name $modulename -AutomationAccountName $automationAccountName -ResourceGroupName $ResourcegroupName
    }

    #Importe powershell file to Runbooks
    Import-AzureRmAutomationRunbook -Path "C:\RemoveAccount.ps1" -Name $runbookName -Type PowerShell -ResourceGroupName $ResourcegroupName -AutomationAccountName $automationAccountName -Force

    #Publishing Runbook
    Publish-AzureRmAutomationRunbook -Name $runbookName -ResourceGroupName $ResourcegroupName -AutomationAccountName $automationAccountName

    #Providing parameter values to powershell script file
    $params=@{"UserName"=$UserName;"Password"=$Password;"ResourcegroupName"=$ResourcegroupName;"SubscriptionId"=$subsriptionid;"automationAccountName"=$automationAccountName}
    Start-AzureRmAutomationRunbook -Name $runbookName -ResourceGroupName $ResourcegroupName -AutomationAccountName $automationAccountName -Parameters $params