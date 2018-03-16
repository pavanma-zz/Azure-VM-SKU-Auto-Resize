<#
    .Synopsis
        Creates Azure Alerts on the specified VM to Scale Up/Down (Vertical Scaling) SKU size

    .Parameter VMNames
        Specify the target VM Name to which SKU Scale Up/Down to be configured

    .Parameter SubscriptionName
        Specify the name of Azure Sub in which the VM exists

    .Parameter AutomationAccountName
        Name of the Azure Automation Account name (Uses existing/Creates new)

    .Parameter LowerCPUThreshold
        SKU reduces by one if CPU is below this threshold for the specified duration

    .Parameter UpperCPUThreshold
        SKU increases by one if CPU is above this threshold for the specified duration

    .Parameter AlertDurationMinutes
        No.of minutes to Wait before lower/upper CPU thresholds are met

    .Parameter AlertMailAddress
        email address to be notified when alert fires

    .Parameter ResizeWindow
        Specify the resize window time (in UTC) in the format "<DDD> HH:MM-<DDD> HH:MM" e.g., "SAT 00:00-SUN 23:59"

    .Parameter MonitorMemory
        Do not change memory when downsizing (applicable only for 'D' and 'DS' series SKU and only if lower SKU with same memory is available)

    .Parameter DisableAutoResize
        Stops Resize related alerts on the specified VM

    .Example
        Resize-AzureVMSKU.ps1 -VMNames test2pavan -SubscriptionName SEALS-SET-Test-Sub-01 -AutomationAccountName pavanma-aa -LowerCPUThreshold 10 -UpperCPUThreshold 60 -AlertMailAddress mymail@microsoft.com -AlertDurationMinutes 360
        Creates two alerts (Scale Up/Scale Down) to downsize/upsize SKU when average CPU usage is <1 or >4 percentage for 360 minutes on the VM 'test2pavan'

    .Example
        Resize-AzureVMSKU.ps1 -VMNames test2pavan -SubscriptionName SEALS-SET-Test-Sub-01 -AutomationAccountName pavanma-aa -LowerCPUThreshold 10 -AlertMailAddress mymail@microsoft.com -AlertDurationMinutes 360
        Creates one alert (Scale Down) to downsize SKU when average CPU usage is <1 percentage for 360 minutes on the VM 'test2pavan'

    .Notes
        NAME:      Resize-AzureVMSKU.ps1
        AUTHOR:    Pavan Kumar Mayakuntla
        LASTEDIT:  5/12/2017
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [String[]]
    $VMNames,

    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionName,

    [Parameter(Mandatory=$true)]
    [String]
    $AutomationAccountName,

    [Parameter()]
    [String]
    $LowerCPUThreshold,

    [Parameter()]
    [String]
    $UpperCPUThreshold,

    [Parameter(Mandatory=$true)]
    [String]
    $AlertMailAddress,

    [Parameter()]
    [String]
    $ResizeWindow,

    [Parameter()]
    [String]
    $AlertDurationMinutes,

    [Switch]
    $MonitorMemory,

    [Switch]
    $DisableAutoResize
)

$WarningPreference = 'silentlycontinue' # Get-AzureRMResource is giving warnings, ignore pls
$ScaleDownRunbook = 'scaleDownV2Vm-v4.ps1'
$ScheduleScaleDownRunbook = 'Schedule-scaleDownV2Vm-v4.ps1'
$ScaleUpRunbook = 'scaleUpV2Vm-v4.ps1'
$ScheduleScaleUpRunbook = 'Schedule-scaleUpV2Vm-v4.ps1'
$RunAsAccountScript = 'New-RunAsAccount-03312017.ps1'
$flag = 0
$outFolder = "c:\temp\"
$module = 'Azure'
$RunbooksFolder = split-path -parent $MyInvocation.MyCommand.Definition
# Azure allows creating Automation Accounts only in the following reasons
$AALocations = @('japaneast','eastus2','westeurope','southeastasia','southcentralus','uksouth','westcentralus','northeurope','canadacentral','australiasoutheast','centralindia')
if (!$LowerCPUThreshold) { $LowerCPUThreshold = 10 }
if (!$UpperCPUThreshold) { $UpperCPUThreshold = 60 }


# Check Azure module existence
if (!(Get-Module $module -ErrorAction SilentlyContinue)) {
    try {
        Import-Module $module
    }
    catch {
        "ERROR : Failed to load $module module, exiting"
        Exit 1
    }
}
# Prerequisite: Azure 1.5.0 module
if ((get-module azure).version -ge '1.5.0') {
    Write-Verbose "$module module is already loaded"
} else {
    Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Azure module version should be >1.5.0, exiting"
    Exit 1
}

$logName = "Resize-AzureVMSKU-LogFile-" + (Get-Date -format "yyyyMMdd-HHmmss") + ".log"
$logFile = Join-Path $outFolder $logName

Start-Transcript -Path $logFile
Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Starting the script (USER: ${env:username}, COMPUTER: ${env:computername})"

# Query the ARM sub for VM details
Try {
    Get-AzureRmContext -ErrorAction Continue | out-null
}
Catch [System.Management.Automation.PSInvalidOperationException] {
    Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Please login to Azure in the prompt/window"
    Login-AzureRmAccount
}
Select-AzureRmSubscription -SubscriptionName "$SubscriptionName" | out-null
if (!$?) {
    write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Could not login to the sub '$SubscriptionName' with error:", $ERROR[0].exception.message
}

# Get VM details
$VMObjects = Get-AzureRmResourceGroup | Get-AzureRmVM
# Query/Create Azure Automation Account Name
if ($AAObject = @(Get-AzureRmResourceGroup | Get-AzureRmAutomationAccount | where {$_.AutomationAccountName -eq $AutomationAccountName})[0]) {
    write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Found Azure Automation account '$AutomationAccountName', using the same.."
} else {
    write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": WARN : Could not find Azure Automation account '$AutomationAccountName', creating.."
    # Create Azure Automation account in the same RG/Location of VM
    # Automation accounts are allowed to be created only in select regions
    $VMObject1 = $VMObjects | where {$_.name -eq $VMNames[0]}
    $VMName1 = $VMObject.Name
    $AALocation = $VMObject1.Location
    if ($VMObject1.Location -notcontains $AALocations) {
        # Default to the below if VM exists in other locations
        $AALocation = 'southcentralus'
        write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": VERB : Creating '$AutomationAccountName' in $AALocation"
    }
    if ($AAObject = New-AzurermAutomationAccount -Name $AutomationAccountName -ResourceGroupName $VMObject1.ResourceGroupName -Location $AALocation) {
        write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Successfully created Azure Automation account '$AutomationAccountName' in '$AALocation' region"
        # Create RunAs Account
        $RunAsAccountPath = Join-Path $RunbooksFolder $RunAsAccountScript
        $appDispName = $VMName1 + "_TestAppDisp"
        $rgName = $VMObject1.ResourceGroupName
        $subId = $AAObject.SubscriptionId
        write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO :     Creating RunAs account '$AutomationAccountName' -- pls login if you get authentication prompt"
        $cmd = "$RunAsAccountPath -ResourceGroup $rgName -AutomationAccountName $AutomationAccountName -ApplicationDisplayName '$appDispName' -SubscriptionId $subId -CreateClassicRunAsAccount 0 -SelfSignedCertPlainPassword 'password'"
        Invoke-Expression $cmd
    } else {
        write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Failed to create Azure Automation account '$AutomationAccountName' with error:  $ERROR[0]"
        Stop-Transcript
        Exit 1
    }
}

# Import Azure Runbooks
Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Importing Runbooks necessary to auto resize VM SKU.."
foreach ($rb in ($ScheduleScaleDownRunbook, $ScaleDownRunbook, $ScheduleScaleUpRunbook, $ScaleUpRunbook)) {
    $RunbookPath = Join-Path $RunbooksFolder $rb
    # Resource Group name is the AA's RG name (not VM's)
    $rg = $AAObject.ResourceGroupName
    if (Import-AzureRmAutomationRunbook -Path "$RunbookPath" -Name "$rb" -ResourceGroupName $rg -AutomationAccountName "$AutomationAccountName" -Type PowerShell -Published -Force) {
        Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": DEBUG:     Importing '$rb'..."
        Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO :     Successfully imported Runbook '$rb'"
    } else {
        Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO :     Failed to import Runbook '$rb' with error:", $ERROR[0].exception.message
        Stop-Transcript
        Exit 1
    }
}

# XXX: Some cleanup/optimization has to be done below.  The tool was written with one VM as target, and modified for multiple VMs as target.  Looping is added now.
foreach ($VMName in ($VMNames | sort | uniq)) {
# Fetch VM properties in the subscription
write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : ========================================================"
write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": DEBUG: Checking VM '$VMName' details in sub '$SubscriptionName'"
if ($VMObject = @($VMObjects | where {$_.Name -eq $VMName})[0]) {
    write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Fetched VM '$VMName' details from sub '$SubscriptionName'"
    $tags = $VMObject.tags
    if ($ResizeWindow) {
        write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Found scheduled resize window;  Tagging VM with the window.."
        # XXX: to be added: validate the resize window syntax
        if ($tags.keys -contains "Auto-Resize-SKU-Window") {
            $tags["Auto-Resize-SKU-Window"] = "$ResizeWindow"
        } else {
            $tags += @{"Auto-Resize-SKU-Window"="$ResizeWindow"}
        }
        if (Set-AzureRmResource -ResourceGroupName $VMObject.ResourceGroupName -Name $VMName -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force) {
            write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Set Auto-Resize-SKU-Window tag for the VM '$VMName'"
        } else {
            write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Failed to set Auto-Resize-SKU-Window tag for the VM '$VMName'"
            Stop-Transcript
            Exit 1
        }
    } else {
        if ($tags.keys -contains "Auto-Resize-SKU-Window") {
            $tags.Remove("Auto-Resize-SKU-Window") | out-null
            if (Set-AzureRmResource -ResourceGroupName $VMObject.ResourceGroupName -Name $VMName -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force) {
                write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : No scheduled resize window; Removed Auto-Resize-SKU-Window tag for the VM '$VMName'"
            } else {
                write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Failed to remove Auto-Resize-SKU-Window tag for the VM '$VMName'"
            }
        }
    }
    if ($MonitorMemory) {
        write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Found monitor memory flag;  Tagging VM with it.."
        if ($tags.keys -contains "Auto-Resize-Monitor-Memory") {
            $tags["Auto-Resize-Monitor-Memory"] = "Yes"
        } else {
            $tags += @{"Auto-Resize-Monitor-Memory"="Yes"}
        }
        if (Set-AzureRmResource -ResourceGroupName $VMObject.ResourceGroupName -Name $VMName -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force) {
            write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Set Auto-Resize-Monitor-Memory tag for the VM '$VMName'"
        } else {
            write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Failed to set Auto-Resize-Monitor-Memory tag for the VM '$VMName'"
            Stop-Transcript
            Exit 1
        }
    } else {
        if ($tags.keys -contains "Auto-Resize-Monitor-Memory") {
            $tags.Remove("Auto-Resize-Monitor-Memory") | out-null
            if (Set-AzureRmResource -ResourceGroupName $VMObject.ResourceGroupName -Name $VMName -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force) {
                write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : No monitor memory flag; Removed Auto-Resize-Monitor-Memory tag for the VM '$VMName'"
            } else {
                write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Failed to remove Auto-Resize-Monitor-Memory tag for the VM '$VMName'"
            }
        }
    }
} else {
    write-host (Get-Date -format "yyyyMMdd HH:mm:ss") ": ERROR: Could not fetch VM '$VMName' details in sub '$SubscriptionName' with error:", $ERROR[0].exception.message
    Stop-Transcript
    Exit 1
}

# Create webhook to trigger the runbooks
Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Creating webhooks necessary to auto resize VM SKU.."
# Note: creation of webhook gives URI which can't be retrieved, so create one at the time of provisioning VM
# Note: Intentionally did not group the sections (Runbooks, webhooks, alerts)
# Scale down webhook
if ($LowerCPUThreshold) {
    $sd_whName = $VMName + "_webhook_" + (Get-Date -format "yyyyMMdd-HHmmss")
    # Set scheduled ScaleDown runbook incase schedule is defined
    if ($ResizeWindow) { 
        $sdRunbook = $ScheduleScaleDownRunbook
    } else {
        $sdRunbook = $ScaleDownRunbook
    }
    $rg = $AAObject.ResourceGroupName
    if ($scaleDown_Webhook = New-AzureRmAutomationWebhook -ResourceGroupName $rg -AutomationAccountName $AutomationAccountName -RunbookName $sdRunbook -IsEnabled $True -ExpiryTime "10/2/2026" -Name "$sd_whName" -Force) {
        Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO :     Successfully created webhook '$sd_whName'"
    } else {
        Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO :     Failed to create webhook '$sd_whName' with error:", $ERROR[0].exception.message
    }
}
# Scale up webhook
if ($UpperCPUThreshold) {
    $su_whName = $VMName + "_webhook_" + (Get-Date -format "yyyyMMdd-HHmmss")
    # Set scheduled ScaleDown runbook incase schedule is defined
    if ($ResizeWindow) { 
        $suRunbook = $ScheduleScaleUpRunbook
    } else {
        $suRunbook = $ScaleUpRunbook
    }
    $rg = $AAObject.ResourceGroupName
    if ($scaleUp_Webhook = New-AzureRmAutomationWebhook -ResourceGroupName $rg -AutomationAccountName $AutomationAccountName -RunbookName $suRunbook -IsEnabled $True -ExpiryTime "10/2/2026" -Name "$su_whName" -Force) {
        Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO :     Successfully created webhook '$su_whName'"
    } else {
        Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO :     Failed to create webhook '$su_whName' with error:", $ERROR[0].exception.message
    }
}

# Creation of alerts
#   Convert Alert duration (time to monitor before firing alert) to window size
#   The below two alerts could be clubbed but kept separate for better clarity
# Scale Down Alert
if (!$AlertDurationMinutes) { $AlertDurationMinutes = 720 } # Default 720 minutes
$a = New-TimeSpan -Minutes $AlertDurationMinutes
$windowSize = get-date -Minute $a.minutes -hour $a.hours -second $a.seconds -Format HH:mm:ss
$actionEmail = New-AzureRmAlertRuleEmail -CustomEmail $AlertMailAddress
if ($LowerCPUThreshold) {
    $actionWebhook = New-AzureRmAlertRuleWebhook -ServiceUri $scaleDown_Webhook.WebhookURI
    $scriptPath = $MyInvocation.MyCommand.Path
    $alertTime = (Get-Date -format "yyyyMMdd HH:mm:ss")
    # There is no way to find alert and its associated runbook/webhook/automation account as webhook URI is not advertised in webhooks.  Capture all this in alert description for reference/troubleshooting purposes
    $targetResourceID = $VMObject.Id
    $rg = $VMObject.ResourceGroupName
    if ($DisableAutoResize) {
        if (Add-AzureRmMetricAlertRule -DisableRule -Threshold $LowerCPUThreshold -Operator lessthan -TargetResourceId "$targetResourceID" -Name "Auto ScaleDown VM SKU - $VMName" -WindowSize $windowSize -MetricName "Percentage CPU" -TimeAggregationOperator Average -Location $VMObject.Location -Description "Scale Down VM size by one SKU at a time. Created by (USER: ${env:username}, COMPUTER: ${env:computername}) using $scriptPath at $alertTime. Triggers Webhook '$sd_whName' which invokes '$sdRunbook' under '$AutomationAccountName' automation account; Memory Flag: $MonitorMemory" -ResourceGroup $rg -Actions $actionEmail,$actionWebhook) {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Successfully disabled 'Scale Down alert' on VM '$VMName' (PercentageCPU lessThan $LowerCPUThreshold for $windowSize, email: $AlertMailAddress)"
        } else {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Failed to disable 'Scale Down alert' on VM '$VMName':", $ERROR[0].exception.message
        }
    } else {
        if (Add-AzureRmMetricAlertRule -Threshold $LowerCPUThreshold -Operator lessthan -TargetResourceId "$targetResourceID" -Name "Auto ScaleDown VM SKU - $VMName" -WindowSize $windowSize -MetricName "Percentage CPU" -TimeAggregationOperator Average -Location $VMObject.Location -Description "Scale Down VM size by one SKU at a time. Created by (USER: ${env:username}, COMPUTER: ${env:computername}) using $scriptPath at $alertTime. Triggers Webhook '$sd_whName' which invokes '$sdRunbook' under '$AutomationAccountName' automation account; Memory Flag: $MonitorMemory" -ResourceGroup $rg -Actions $actionEmail,$actionWebhook) {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Successfully created 'Scale Down alert' on VM '$VMName' (PercentageCPU lessThan $LowerCPUThreshold for $windowSize, email: $AlertMailAddress)"
        } else {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Failed to create 'Scale Down alert' on VM '$VMName':", $ERROR[0].exception.message
        }
    }
}
# Scale Down Alert
if ($UpperCPUThreshold) {
    $actionWebhook = New-AzureRmAlertRuleWebhook -ServiceUri $scaleUp_Webhook.WebhookURI
    $scriptPath = $MyInvocation.MyCommand.Path
    $alertTime = (Get-Date -format "yyyyMMdd HH:mm:ss")
    # There is no way to find alert and its associated runbook/webhook/automation account as webhook URI is not advertised in webhooks.  Capture all this in alert description for reference/troubleshooting purposes
    $targetResourceID = $VMObject.Id
    if ($DisableAutoResize) {
        if (Add-AzureRmMetricAlertRule -DisableRule -Threshold $UpperCPUThreshold -Operator GreaterThan -TargetResourceId "$targetResourceID" -Name "Auto ScaleUp VM SKU - $VMName" -WindowSize $windowSize -MetricName "Percentage CPU" -TimeAggregationOperator Average -Location $VMObject.Location -Description "Scale Up VM size by one SKU at a time. Created by (USER: ${env:username}, COMPUTER: ${env:computername}) using $scriptPath at $alertTime. Triggers Webhook '$su_whName' which invokes '$suRunbook' under '$AutomationAccountName' automation account; Memory Flag: $MonitorMemory" -ResourceGroup $VMObject.ResourceGroupName -Actions $actionEmail,$actionWebhook) {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Successfully disabled 'Scale Up alert' on VM '$VMName' (PercentageCPU greaterThan $UpperCPUThreshold for $windowSize, email: $AlertMailAddress)"
        } else {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Failed to disable 'Scale Up alert' on VM '$VMName':", $ERROR[0].exception.message
        }
    } else {
        if (Add-AzureRmMetricAlertRule -Threshold $UpperCPUThreshold -Operator GreaterThan -TargetResourceId "$targetResourceID" -Name "Auto ScaleUp VM SKU - $VMName" -WindowSize $windowSize -MetricName "Percentage CPU" -TimeAggregationOperator Average -Location $VMObject.Location -Description "Scale Up VM size by one SKU at a time. Created by (USER: ${env:username}, COMPUTER: ${env:computername}) using $scriptPath at $alertTime. Triggers Webhook '$su_whName' which invokes '$suRunbook' under '$AutomationAccountName' automation account; Memory Flag: $MonitorMemory" -ResourceGroup $VMObject.ResourceGroupName -Actions $actionEmail,$actionWebhook) {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Successfully created 'Scale Up alert' on VM '$VMName' (PercentageCPU greaterThan $UpperCPUThreshold for $windowSize, email: $AlertMailAddress)"
        } else {
            Write-Host (Get-Date -format "yyyyMMdd HH:mm:ss") ": INFO : Failed to create 'Scale Up alert' on VM '$VMName':", $ERROR[0].exception.message
        }

    }
}
}

Stop-Transcript
