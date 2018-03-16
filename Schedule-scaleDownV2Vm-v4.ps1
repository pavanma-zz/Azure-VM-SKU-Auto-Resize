<# 
.SYNOPSIS 
  Connects to Azure and vertically scales down the VM based on schedule
 
.DESCRIPTION 
  This runbook connects to Azure and schedules runbook that scales down the VM  
 
  REQUIRED AUTOMATION ASSETS 
  1. An Automation connection asset called "AzureRunAsConnection" that contains the information for authenticating with Azure. 
 
.PARAMETER VmName 
   Optional  
   The VM to scale.  Set this parameter when you don't start the runbook from a VM alert.' 
 
.PARAMETER ResourceGroupName 
   Optional  
   The resource group that the VM is in.  Set this parameter when you don't start the runbook from a VM alert.'
 
.PARAMETER AutomationAccountName
   Optional  
   Automation Account under which the runbook exists.  Set this parameter when you don't start the runbook from a VM alert.'
 
.PARAMETER WebhookData 
   Optional  
   When triggered from a VM alert rule, this parameter will be passed 
 
.NOTES 
   AUTHOR: Azure Compute Team  
   LASTEDIT: 2016-6-11 
   NOTE: Original script from Azure Compute Team.  Modified it as per the requirements.
        MODIFIED BY: Pavan Kumar Mayakuntla
        LASTEDIT: 2017-04-27
#> 
 
# Returns strings with status messages 
[OutputType([String])] 
 
param  
( 
    [parameter(Mandatory=$false)] 
    [string] $VmName, 
     
    [parameter(Mandatory=$false)] 
    [string] $ResourceGroupName, 

    [parameter(Mandatory=$false)] 
    [string] $AutoAccName, 
 
    [parameter(Mandatory=$false)] 
    [object]$WebhookData 
) 
 
if ($WebhookData) 
{ 
    # This runbook is being started from an alert 
    # Get parameters from WebhookData 
    $WebhookBody = $WebhookData.RequestBody 
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookBody) 
    if ($WebhookBody.status -ne "Activated") 
    { 
        $DoIt = $false 
        Write-Output "`nAlert not activated" 
    } 
    else 
    { 
        $DoIt = $true 
        $AlertContext = [object]$WebhookBody.context 
        $ResourceGroupName = $AlertContext.resourceGroupName 
        $VmName = $AlertContext.resourceName 
        # Get Azure Automation Account Name
        # XXX: Description dependency will be removed in next version
        $WebhookDesc = $AlertContext.description
        write-output "Alert description: "  $WebhookDesc
        if ($webhookdesc -match "under \'(.*?)\' automation account") {
            $AutoAccName = $matches[1]
            Write-Output "Automation Account Name: $AutoAccName"
        }
    } 
} 
elseif (!$VmName -or !$ResourceGroupName -or !$AutoAccName) 
{ 
    # Necessary input parameters have not been set 
    $DoIt = $false 
    throw "This runbook is missing required input parameters.  Either WebhookData or VmName and ResourceGroupName and AutomationAccount must be provided." 
} 
else 
{ 
    $DoIt = $true 
} 

if ($DoIt)  
{ 
    # Perform the schedule scale action 
    # Authenticate to Azure with service principal and certificate and set subscription 
    $ConnectionAssetName = "AzureRunAsConnection" 
    $Conn = Get-AutomationConnection -Name $ConnectionAssetName 

    if ($Conn -eq $null) 
    { 
        throw "Could not retrieve connection asset: $ConnectionAssetName. Assure that this asset exists in the Automation account." 
    } 
    $null = Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint -ErrorAction Stop 
    $null = Set-AzureRmContext -SubscriptionId $Conn.SubscriptionId -ErrorAction Stop 
    <# 
    # Connect to Azure with credential and select the subscription to work against 
    $Cred = Get-AutomationPSCredential -Name 'AzureCredential' 
    $null = Add-AzureRmAccount -Credential $Cred -ErrorAction Stop 
    $SubId = Get-AutomationVariable -Name 'AzureSubscriptionId' 
    $null = Set-AzureRmContext -SubscriptionId $SubId -ErrorAction Stop 
    #> 

    try  
    { 
        $vm = Get-AzureRmVm -ResourceGroupName $ResourceGroupName -VMName $VmName -ErrorAction Stop 
    }  
    catch  
    { 
        Write-Error "Virtual Machine not found: $VmName" 
        exit 
    }
    # Read auto resize window tag
    $ResizeWindow = $vm.Tags['Auto-Resize-SKU-Window']
    if ($ResizeWindow) {
        Write-Output "Resize window of the VM $VmName at window $ResizeWindow" 
    } else {
        Write-Error "Could not find tag for resize window.  Exiting.." 
        exit
    }
    $rStart = $ResizeWindow -split " "| foreach {$_.Trim()}
    if($rStart.Count -eq 2) {
        $targetDay = $rStart[0]
        $targetTime = $rStart[1]
        $daysHash = @{"Sun" = 1; "Mon" = 2; "Tue" = 3; "Wed" = 4; "Thu" = 5; "Fri" = 6; "Sat" = 7}
        # Find the no.of days to add
        # 7 - current day + target day
        $daysToAdd =(7-($daysHash[(get-date -UFormat "%a")])+($daysHash[$targetDay]))%7
        #if ($daysToAdd -eq 0) { $daysToAdd = 7 }
        $resizeDate = (Get-Date $targetTime) + (New-TimeSpan -Days $daysToAdd)
        Write-Output $resizeDate
    }
# Reference:
# New-AzureRmAutomationSchedule -AutomationAccountName 'pavanma-aa' -Name "test2pavan-auto-resize" -StartTime "4/29/2017 23:00" -OneTime -ResourceGroupName "TestRGForPavan" -TimeZone $TimeZone
# Register-AzureRmAutomationScheduledRunbook -AutomationAccountName 'pavanma-aa' -Name "scaleUpV2Vm-v4.ps1" -ScheduleName "test2pavan-auto-resize" -ResourceGroupName "TestRGForPavan"

    $scheduleName = $VmName + "-auto-resize"
    $AutoAccNameRG = @((get-azurermautomationaccount | where {$_.AutomationAccountName -eq $AutoAccName})[0]).ResourceGroupName
    $TimeZone = ([System.TimeZoneInfo]::Local).Id
    write-host "TimeZone: $TimeZone"
    # Delete existing schedule as it may be expired and also schedule starttime cannot be modified.  Delete and create new
#if (Get-AzureRmAutomationSchedule -AutomationAccountName "pavanma-aa" -Name scheduleName -ResourceGroupName "TestRGForPavan") {
    if (Get-AzureRmAutomationSchedule -Name $scheduleName -AutomationAccountName $AutoAccName -ResourceGroupName $AutoAccNameRG -ErrorAction SilentlyContinue) {
        Write-Output "Deleting existing schedule $scheduleName -- could be expired, hence.." 
        Remove-AzureRmAutomationSchedule -Name $scheduleName  -AutomationAccountName $AutoAccName -ResourceGroupName "$AutoAccNameRG" -Force
    }
    #if (New-AzureRmAutomationSchedule  -AutomationAccountName $AutoAccName -ResourceGroupName $AutoAccNameRG -Name $scheduleName -StartTime $resizeDate -OneTime -TimeZone $TimeZone) {
    if (New-AzureRmAutomationSchedule  -AutomationAccountName $AutoAccName -ResourceGroupName $AutoAccNameRG -Name $scheduleName -StartTime $resizeDate -OneTime) {
        Write-Output "Created schedule $scheduleName at $ResizeWindow" 
    } else {
        Write-Error "Could not create schedule $scheduleName .  Exiting.." 
        exit
    }
    $params = @{"VMName" = $VmName; "ResourceGroupName" = $ResourceGroupName}
    if (Register-AzureRmAutomationScheduledRunbook -Name "scaleDownV2Vm-v4.ps1" -ScheduleName $scheduleName  -AutomationAccountName $AutoAccName -ResourceGroupName $AutoAccNameRG -Parameters $params) {
        Write-Output "Linked runbook with schedule $scheduleName " 
    } else {
        Write-Error "Could not link runbook with schedule $scheduleName.  Exiting.." 
        exit
    }
}
