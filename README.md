# Azure-VM-SKU-Auto-Resize
PowerShell Scripts to deploy Azure VM SKU Resize (vertical scaling) feature for Azure VMs

Background

As part of Azure cost optimization, it’s best to right size VM SKU based on its usage.  Azure provides mechanisms to do it, it requires creating various components (listed below) and configuring it which usually takes few hours/days to familiarize the components, do POCs, plan deployment meticulously to have good tracking of mapping of these components.
-	Authoring & Creating of various Azure Runbooks
-	Creation of Azure Automation accounts
-	Creation of Webhooks to trigger Runbooks
-	Creation of Azure alert on the VM

Tool features

This self-help PowerShell tool enables businesses to configure/schedule VM Auto Resizing based on CPU/Memory* usage/Disk count.

Functionality: 
1)	Monitor CPU and memory* (optional) usage and resize (downsize/upsize) VM SKU automatically.  E.g., CPU <10% for 12Hrs, downsize SKU by one. 
	By default, resizes only based on CPU usage – e.g., from DS14 to DS13… DS1.  This is ideal for non-prod servers and most of production unless memory is a concern.
	Considering memory usage is not straight forward as it requires enabling diagnostics and enable memory counters.  Without enabling diagnostics and memory counters, to help with memory intensive apps, downsize/upsize to lower SKUs but with same memory.  This is ideal for prod servers incase memory is a concern. 
•	E.g, if SKU is DS4 (8cores, 28GB), downsize to only DS13 (4cores, 28GB) where memory is same.  For all downsize/upsize requirements, it flips between only these 2 CPUs.  This is still 35% cost effective (from DS4 to DS13).
* Monitoring memory counters is not available natively in Azure fabric unless diagnostics are enabled and memory counters are monitored and data is written to storage accounts.  To circumvent scenarios where downsizing to lower memory SKUs, is not acceptable, flip only between CPUs with same memory (DS4 (8cores,28GB) <-> DS13 (4cores,28GB)).
2)	SKU Resize requires reboot , so added scheduled reboot feature where automation resizes only in the specified schedule (say, every Sat at 1am)
3)	Disable auto-resize feature at will when you want to turn down for already targeted VMs

End-user Experience/Usability
1)	End-to-end automation via PowerShell – no need to be knowledgeable about the relevant Azure components nor additional touch points for setting this up
2)	Onboard multiple VMs from a subscription in one go
3)	Onboarding time is about a minute per VM
4)	Just input the below parameters to the tool: 
	Names of the VMs
	Name of the Sub
	Automation Account Name
	Email address
	Optional parameters: 
•	Thresholds (Upper and Lower CPU values to trigger Upsize/Downsize respectively e.g., 10% and 60%)
•	Duration to monitor before triggering resize (e.g., last 12Hrs)
•	Monitor memory flag (for flipping between CPUs without reducing memory allotment)

Constraints

- Tool looks at CPU, Memory* (optional), Disk count while downsizing or upsizing.
* there is no way to query memory usage natively from Azure fabric unless diagnostics are enabled to monitor memory counters.  Customer can choose to select/unselect memory parameter while configuring ‘auto-resize’ for the VMs.

How to use


