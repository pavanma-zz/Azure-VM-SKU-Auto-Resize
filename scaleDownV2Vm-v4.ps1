<# 
.SYNOPSIS 
  Connects to Azure and vertically scales down the VM 
 
.DESCRIPTION 
  This runbook connects to Azure and scales down the VM  
 
  REQUIRED AUTOMATION ASSETS 
  1. An Automation connection asset called "AzureRunAsConnection" that contains the information for authenticating with Azure. 
 
.PARAMETER VmName 
   Optional  
   The VM to scale.  Set this parameter when you don't start the runbook from a VM alert.' 
 
.PARAMETER ResourceGroupName 
   Optional  
   The resource group that the VM is in.  Set this parameter when you don't start the runbook from a VM alert.'

.PARAMETER WebhookData 
   Optional  
   When triggered from a VM alert rule, this parameter will be passed 
 
.NOTES 
   AUTHOR: Azure Compute Team  
   LASTEDIT: 2016-6-11 
   NOTE: Original script from Azure Compute Team.  Modified it as per the requirements.
        MODIFIED BY: Pavan Kumar Mayakuntla
        LASTEDIT: 2017-05-15
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
    } 
} 
elseif (!$VmName -or !$ResourceGroupName) 
{ 
    # Necessary input parameters have not been set 
    $DoIt = $false 
    throw "This runbook is missing required input parameters.  Either WebhookData or VmName and ResourceGroupName must be provided." 
} 
else 
{ 
    $DoIt = $true 
} 
     
if ($DoIt)  
{ 
    # Perform the scale action 
     
    $noResize = "noresize" 
     
    $scaleDown = @{ 
        "Standard_A0"      = $noResize 
        "Standard_A1"      = "Standard_A0" 
        "Standard_A2"      = "Standard_A1" 
        "Standard_A3"      = "Standard_A2" 
        "Standard_A4"      = "Standard_A3" 
        "Standard_A5"      = "Standard_A3" # A4 is costler than A5
        "Standard_A6"      = "Standard_A5" 
        "Standard_A7"      = "Standard_A6" 
        "Standard_A8"      = "Standard_A6" # No diff between A8 and A7 in conf, so go for A6
        "Standard_A9"      = "Standard_A8" 
        "Standard_A10"     = "Standard_A8" # A9 is costlier and upgrade infact, so A8
        "Standard_A11"     = "Standard_A10" 
        "Standard_A1_v2"   = $noResize
        "Standard_A2_v2"   = "Standard_A1_v2"
        "Standard_A4_v2"   = "Standard_A2_v2"
        "Standard_A8_v2"   = "Standard_A4_v2"
        "Standard_A2m_v2"  = $noResize
        "Standard_A4m_v2"  = "Standard_A2m_v2"
        "Standard_A8m_v2"  = "Standard_A4m_v2"
        "Basic_A0"         = $noResize 
        "Basic_A1"         = "Basic_A0" 
        "Basic_A2"         = "Basic_A1" 
        "Basic_A3"         = "Basic_A2" 
        "Basic_A4"         = "Basic_A3" 
        "Standard_D1_v2"   = $noResize 
        "Standard_D2_v2"   = "Standard_D1_v2" 
        "Standard_D3_v2"   = "Standard_D2_v2" 
        "Standard_D4_v2"   = "Standard_D3_v2" 
        "Standard_D5_v2"   = "Standard_D4_v2" 
        "Standard_DS1_v2"  = $noResize
        "Standard_DS2_v2"  = "Standard_DS1_v2"
        "Standard_DS3_v2"  = "Standard_DS2_v2"
        "Standard_DS4_v2"  = "Standard_DS3_v2"
        "Standard_DS5_v2"  = "Standard_DS4_v2"
        "Standard_D11_v2"  = "Standard_D2_v2" # D2_v2 is cheaper 
        "Standard_D12_v2"  = "Standard_D11_v2" 
        "Standard_D13_v2"  = "Standard_D12_v2" 
        "Standard_D14_v2"  = "Standard_D13_v2" 
        "Standard_D15_v2"  = "Standard_D14_v2" 
        "Standard_DS1"     = $noResize 
        "Standard_DS2"     = "Standard_DS1" 
        "Standard_DS3"     = "Standard_DS2" 
        "Standard_DS4"     = "Standard_DS3" 
        "Standard_DS11"    = "Standard_DS2" # DS2 is cheaper
        "Standard_DS12"    = "Standard_DS11" 
        "Standard_DS13"    = "Standard_DS12" 
        "Standard_DS14"    = "Standard_DS13" 
        "Standard_DS11_v2" = "Standard_DS2_v2" # DS2_v2 is cheaper
        "Standard_DS12_v2" = "Standard_DS11_v2"
        "Standard_DS13_v2" = "Standard_DS12_v2"
        "Standard_DS14_v2" = "Standard_DS13_v2"
        "Standard_DS15_v2" = "Standard_DS14_v2"
        "Standard_D1"      = $noResize 
        "Standard_D2"      = "Standard_D1" 
        "Standard_D3"      = "Standard_D2" 
        "Standard_D4"      = "Standard_D3"  
        "Standard_D11"     = "Standard_D2" # D2 is cheaper
        "Standard_D12"     = "Standard_D11" 
        "Standard_D13"     = "Standard_D12" 
        "Standard_D14"     = "Standard_D13" 
        "Standard_G1"      = $noResize 
        "Standard_G2"      = "Standard_G1" 
        "Standard_G3"      = "Standard_G2"  
        "Standard_G4"      = "Standard_G3"   
        "Standard_G5"      = "Standard_G4"  
        "Standard_GS1"     = $noResize 
        "Standard_GS2"     = "Standard_GS1" 
        "Standard_GS3"     = "Standard_GS2" 
        "Standard_GS4"     = "Standard_GS3" 
        "Standard_GS5"     = "Standard_GS4" 
    } 
    # If memory shouldn't be downgraded, flip between pairs (e.g., Standard_D12_v2 (4 cores, 28GB) and Standard_D4_v2 (8 cores, 28GB))
    $scaleDown_Memory = @{ 
        "Standard_A0"      = $noResize 
        "Standard_A1"      = "Standard_A0" 
        "Standard_A2"      = "Standard_A1" 
        "Standard_A3"      = "Standard_A2" 
        "Standard_A4"      = "Standard_A5" # A5 (14GB, 2 cores) from A4 (14gb, 8 cores) 
        "Standard_A5"      = $noResize 
        "Standard_A6"      = "Standard_A5" 
        "Standard_A7"      = "Standard_A6" 
        "Standard_A8"      = $noResize 
        "Standard_A9"      = "Standard_A8" 
        "Standard_A10"     = $noResize 
        "Standard_A11"     = "Standard_A10" 
        "Standard_A1_v2"   = $noResize
        "Standard_A2_v2"   = "Standard_A1_v2"
        "Standard_A4_v2"   = "Standard_A2_v2"
        "Standard_A8_v2"   = "Standard_A4_v2"
        "Standard_A2m_v2"  = $noResize
        "Standard_A4m_v2"  = "Standard_A2m_v2"
        "Standard_A8m_v2"  = "Standard_A4m_v2"
        "Basic_A0"         = $noResize 
        "Basic_A1"         = "Basic_A0" 
        "Basic_A2"         = "Basic_A1" 
        "Basic_A3"         = "Basic_A2" 
        "Basic_A4"         = "Basic_A3" 
        "Standard_D1_v2"   = $noResize 
        "Standard_D2_v2"   = "Standard_D1_v2" 
        "Standard_D3_v2"   = "Standard_D11_v2" # DS3_v2 and DS11_v2 are pairs (both 14GB, cores 4 and 2 respectively)
        "Standard_D4_v2"   = "Standard_D12_v2" # DS4_v2 and DS12_v2 are pairs (both 28GB, cores 8 and 4 respectively) 
        "Standard_D5_v2"   = "Standard_D13_v2" # DS5_v2 and DS12_v2 are pairs (both 28GB, cores 8 and 4 respectively) 
        "Standard_DS1_v2"  = $noResize
        "Standard_DS2_v2"  = "Standard_DS1_v2"
        "Standard_DS3_v2"  = "Standard_DS11_v2" # DS3_v2 and DS11_v2 are pairs (both 14GB, cores 4 and 2 respectively)
        "Standard_DS4_v2"  = "Standard_DS12_v2" # DS4_v2 and DS12_v2 are pairs (both 28GB, cores 8 and 4 respectively)
        "Standard_DS5_v2"  = "Standard_DS13_v2"  # DS5_v2 and DS12_v2 are pairs (both 28GB, cores 8 and 4 respectively) 
        "Standard_D11_v2"  = $noResize 
        "Standard_D12_v2"  = "Standard_D11_v2" 
        "Standard_D13_v2"  = "Standard_D12_v2" 
        "Standard_D14_v2"  = "Standard_D13_v2" 
        "Standard_D15_v2"  = "Standard_D14_v2" 
        "Standard_DS1"     = $noResize 
        "Standard_DS2"     = "Standard_DS1" 
        "Standard_DS3"     = "Standard_DS11"  # DS3 and DS11 are pairs (both 14GB, cores 4 and 2 respectively)
        "Standard_DS4"     = "Standard_DS12"  # DS4 and DS12 are pairs (both 28GB, cores 8 and 4 respectively)
        "Standard_DS11"    = $noResize 
        "Standard_DS12"    = "Standard_DS11" 
        "Standard_DS13"    = "Standard_DS12" 
        "Standard_DS14"    = "Standard_DS13" 
        "Standard_DS11_v2" = $noResize
        "Standard_DS12_v2" = "Standard_DS11_v2"
        "Standard_DS13_v2" = "Standard_DS12_v2"
        "Standard_DS14_v2" = "Standard_DS13_v2"
        "Standard_DS15_v2" = "Standard_DS14_v2"
        "Standard_D1"      = $noResize 
        "Standard_D2"      = "Standard_D1" 
        "Standard_D3"     = "Standard_D11"  # DS3 and DS11 are pairs (both 14GB, cores 4 and 2 respectively)
        "Standard_D4"     = "Standard_D12"  # DS4 and DS12 are pairs (both 28GB, cores 8 and 4 respectively) 
        "Standard_D11"     = $noResize 
        "Standard_D12"     = "Standard_D11" 
        "Standard_D13"     = "Standard_D12" 
        "Standard_D14"     = "Standard_D13" 
        "Standard_G1"      = $noResize 
        "Standard_G2"      = "Standard_G1" 
        "Standard_G3"      = "Standard_G2"  
        "Standard_G4"      = "Standard_G3"   
        "Standard_G5"      = "Standard_G4"  
        "Standard_GS1"     = $noResize 
        "Standard_GS2"     = "Standard_GS1" 
        "Standard_GS3"     = "Standard_GS2" 
        "Standard_GS4"     = "Standard_GS3" 
        "Standard_GS5"     = "Standard_GS4" 

    } 

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

    $currentVMSize = $vm.HardwareProfile.vmSize 
     
    Write-Output "`nFound the specified Virtual Machine: $VmName" 
    Write-Output "Current size: $currentVMSize" 

    $newVMSize = "" 
    # Read auto resize window tag; Scale down without modifying memory
    $MonitorMemory = $vm.Tags['Auto-Resize-Monitor-Memory']
    if ($MonitorMemory -eq 'Yes') {
        Write-Output "Monitor memory flag is set"
        $newVMSize = $scaleDown_Memory[$currentVMSize]
    } else {
        $newVMSize = $scaleDown[$currentVMSize] 
    }
    if($newVMSize -eq $noResize)  
    { 
        Write-Output (Get-Date -format "yyyyMMdd HH:mm:ss") "Sorry the current Virtual Machine size $currentVMSize can't be scaled down. You'll need to recreate the specified Virtual Machine with your desired size." 
    }  
    else  
    { 
        Write-Output "`nNew size will be: $newVMSize" 
             
        $vm.HardwareProfile.VmSize = $newVMSize 
        Update-AzureRmVm -VM $vm -ResourceGroupName $ResourceGroupName 
         
        $updatedVm = Get-AzureRmVm -ResourceGroupName $ResourceGroupName -VMName $VmName 
        $updatedVMSize = $updatedVm.HardwareProfile.vmSize 
         
        Write-Output (Get-Date -format "yyyyMMdd HH:mm:ss") "`n $VmName SKU Size updated from $currentVMSize to $updatedVMSize"
    } 
} 