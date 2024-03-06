<#
Created by: Jeffery Field (jfield)
Purpose: Creates a scheduled task to enroll devices into Intune

		:Change Log:
	1/20/23 - initial write
    3/3/23 - Updated the copy portion of the script. Added a second task to Start the enrollment NOW for helpdesk.
             Added portion to create registry keys for auto enrollment
    9/20/23 - Multiple changes. Added more error handling. Added the pre-flight checks. Added task to trigger gpupdate script.

#>

Start-Transcript -Path C:\Windows\Logs\Intune-Migration-Log.txt -Append

$VerbosePreference = "Continue"
$fatalError = $false


#=======================================================================================================================Variables you need to set

$AzureBlobURL = ""

#=======================================================================================================================Variables you need to set


remove-item C:\IT\ScheduledTask -Recurse -Force -Confirm:$false 


#Create some folders
New-Item -ItemType Directory -Path c:\ -Name IT -ErrorAction SilentlyContinue -Verbose
New-Item -ItemType directory -Path c:\IT\ -Name ScheduledTask -ErrorAction SilentlyContinue -Verbose
New-Item -ItemType directory -Path c:\IT\ -Name Files -ErrorAction SilentlyContinue -Verbose


#Make sure the folder got made and copy the ACL from Program files and copy it to new directories
$PathTest = Test-Path -Path C:\IT\ScheduledTask\
Get-Acl 'C:\Program Files' | Set-Acl C:\IT\ScheduledTask -Verbose
Get-Acl 'C:\Program Files' | Set-Acl C:\IT\Files -Verbose


#Switch to the invocaton pat(where the script is on disk) so the cache of intune or WS1
$scriptpath = $MyInvocation.MyCommand.Path
$scriptname = $MyInvocation.MyCommand.name
$dir = Split-Path $scriptpath
Set-Location $dir

Write-Host "Executing $scriptname"

#Copy items from the cache to this path
Copy-Item -Path .\*.ps1 -Destination c:\IT\ScheduledTask\ -Force -Verbose
Copy-Item -Path .\*.exe -Destination c:\IT\ScheduledTask\ -Force -Verbose

New-EventLog -source IT-Script -LogName Application -ErrorAction Continue -Verbose

#---------------------------------------------------------------------------------------------------------------------Create Enrollment task-----------------------------------------------------------------------------------------------------------------

    $taskname="Intune-Enrollment"
    # delete existing task if it exists
    Get-ScheduledTask -TaskName $taskname -ErrorAction SilentlyContinue |  Unregister-ScheduledTask -Confirm:$false
    # get target script based on current script root
    $scriptPath="c:\IT\ScheduledTask\Enroll-Intune.ps1"
    # create list of triggers, and add logon trigger
    $triggers = @()
    #$triggers += New-ScheduledTaskTrigger -AtLogOn

    # create TaskEventTrigger, use your own value in Subscription
    $CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler:MSFT_TaskEventTrigger
    $trigger = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $trigger.Subscription = 
@"
<QueryList><Query Id="0" Path="Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational"><Select Path="Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin">*[System[Provider[@Name='Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider'] and EventID=74]]</Select></Query></QueryList>
"@

    $trigger.Enabled = $True 
    $triggers += $trigger


    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # create task
    $User='Nt Authority\System'
    $Action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-noprofile -nologo -NonInteractive -WindowStyle hidden -executionpolicy bypass -File $scriptPath"
    $Task = Register-ScheduledTask -TaskName $taskname -Trigger $triggers -User $User -Action $Action -RunLevel Highest -Force -Settings $settings
    $task.Triggers.Repetition.Interval = "PT5M"
    $task | Set-ScheduledTask

#Make sure the task got created
Start-Sleep -Seconds 60
$GetTask = Get-ScheduledTask -TaskName $taskName

if($GetTask.State -eq "Ready"){
Write-Host "$taskname task is $($gettask.State)"

}else{
Write-Host "$taskname task is NOT present. Something went wrong"
$fatalError -eq $True
}


#---------------------------------------------------------------------------------------------------------------------Create toast task-----------------------------------------------------------------------------------------------------------------

    $taskname="MDM-Toast"
    # delete existing task if it exists
    Get-ScheduledTask -TaskName $taskname -ErrorAction SilentlyContinue |  Unregister-ScheduledTask -Confirm:$false
    # get target script based on current script root
    $scriptPath="c:\IT\ScheduledTask\Toast.ps1"
    # create list of triggers, and add logon trigger
    $triggers = @()

    # create TaskEventTrigger, use your own value in Subscription
    $CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler:MSFT_TaskEventTrigger
    $trigger = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $trigger.Subscription = 
@"
<QueryList><Query Id="0" Path="Application"><Select Path="Application">*[System[Provider[@Name='IT-Script'] and EventID=1000]]</Select></Query></QueryList>
"@

    $trigger.Enabled = $True 
    $triggers += $trigger


    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # create task
    $principal = New-ScheduledTaskPrincipal -GroupId Users
    $Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument '/c start /min "" powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\IT\ScheduledTask\toast.ps1"'
    $Task = Register-ScheduledTask -TaskName $taskname -Trigger $triggers -principal $principal -Action $Action -Force -Settings $settings
    $task | Set-ScheduledTask


Start-Sleep -Seconds 60
$GetTask = Get-ScheduledTask -TaskName $taskName

if($GetTask.State -eq "Ready"){
Write-Host "$taskname task is $($gettask.State)"

}else{
Write-Host "$taskname task is NOT present. Something went wrong"

}


#---------------------------------------------------------------------------------------------------------------------Create Enroll Intune Now task in case it fails then helpdesk can run this task-----------------------------------------------------------------------------------------------------------------

$taskname = "Enroll-Intune-Now"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$User='Nt Authority\System'
$Action= New-ScheduledTaskAction -Execute "c:\windows\system32\deviceenroller.exe" -Argument "/c /autoenrollmdm"
$Task = Register-ScheduledTask -TaskName $taskname -User $User -Action $Action -RunLevel Highest -Force -Settings $settings

Start-Sleep -Seconds 60
$GetTask = Get-ScheduledTask -TaskName $taskName

if($GetTask.State -eq "Ready"){
Write-Host "$taskname task is $($gettask.State)"

}else{
Write-Host "$taskname task is NOT present. Something went wrong"

}

#---------------------------------------------------------------------------------------------------------------------Set Registry Keys-----------------------------------------------------------------------------------------------------------------

Write-host "Setting Registry Keys"
New-Item -Path HKLM:Software\Policies\Microsoft\Windows\CurrentVersion\ -Name MDM -ErrorAction SilentlyContinue
Set-ItemProperty HKLM:Software\Policies\Microsoft\Windows\CurrentVersion\MDM -Name "AutoEnrollMDM" -Value "1" -Type DWord
Set-ItemProperty HKLM:Software\Policies\Microsoft\Windows\CurrentVersion\MDM -Name "UseAADCredentialType" -Value "1" -Type DWord

$RegKey1 = Get-ItemProperty HKLM:Software\Policies\Microsoft\Windows\CurrentVersion\MDM -Name "AutoEnrollMDM"

if($RegKey1 -ne $null){
Write-Host "AutoEnroll Registry key is set to $($RegKey1.AutoEnrollMDM)"
}else{
Write-Host "ERROR: Reg key is not present"
$fatalError -eq $True
}


#---------------------------------------------------------------------------------------------------------------------Pre-Flight Checks-----------------------------------------------------------------------------------------------------------------


$VerbosePreference = "Continue"

[int]$preflight = 0


$JoinInfo = Test-Path HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo
if($JoinInfo -eq $true){
    [int]$preflight += 1
    Write-Host "JoinInfo is in registry"   
}else{
    Write-Host "Error: JoinInfo Not present. May need to re-run."
}


function Get-DsRegStatus {
    <#
    .Synopsis
    Returns the output of dsregcmd /status as a PSObject.
 
    .Description
    Returns the output of dsregcmd /status as a PSObject. All returned values are accessible by their property name.
 
    .Example
    # Displays a full output of dsregcmd / status.
    Get-DsRegStatus
    #>

    
    $dsregcmd = dsregcmd /status
    $o = New-Object -TypeName PSObject
    $dsregcmd | Select-String -Pattern " *[A-z]+ : [A-z]+ *" | ForEach-Object {
              Add-Member -InputObject $o -MemberType NoteProperty -Name (([String]$_).Trim() -split " : ")[0] -Value (([String]$_).Trim() -split " : ")[1]
         }
    return $o
}

$DSReg = Get-DsRegStatus

Write-Host "AzureAdJoined status is $($DSReg.AzureAdJoined)"

Write-Host "On Prem Joined status is $($DSReg.DomainJoined)"

if($DSReg.AzureAdJoined -eq "Yes" -and $DSReg.DomainJoined -eq "No"){
[int]$preflight += 1
$DSRegSatus = "AzureADJoined"
Write-Host "Device is Azure AD Cloud Joined"
}else{
Write-Host "Device is not Azure AD joined"
}

if($DSReg.AzureAdJoined -eq "Yes" -and $DSReg.DomainJoined -eq "Yes"){
[int]$preflight += 1
$DSRegSatus = "HybridAzureADJoined"
}else{
Write-Host "Device is not Hybrid Azure AD joined"
}

if($DSReg.AzureAdJoined -eq "No" -and $DSReg.DomainJoined -eq "Yes"){
[int]$preflight -= 1
$DSRegSatus = "OnPremOnly"
$FatalError = $true
}else{
Write-Host "Device is not on prem only joined"
}

$VerInfo = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion")

[version]$ver = -join( $VerInfo.CurrentMajorVersionNumber, ".", $VerInfo.CurrentMinorVersionNumber, ".", $VerInfo.CurrentBuild)
[version]$1909 = "10.0.18362"

If($ver -ge $1909){
[int]$preflight += 1
Write-Host "Device is 1909 or higher"
}else{
[int]$preflight -= 1
Write-Host "Fatal Error: Device is NOT 1909 or higher"
$FatalError = $true
}



#Make sure the task got created
$taskname="Intune-Enrollment"
$GetTask = Get-ScheduledTask -TaskName $taskName
if($GetTask.State -eq "Ready"){
Write-Host "Task is $($gettask.State)"
[int]$preflight += 1
}else{
Write-Host "Error: Task is not Present. May need to rerun."
}


$b = Test-Path -Path C:\IT\ScheduledTask\Enroll-Intune.ps1
if($b -eq $true){
Write-Host "PS Script is present."
[int]$preflight += 1
$c = "Script is Present"
}else{
Write-Host "Error: Does not have script. May need to re-run"
$FatalError = $true
}



if($FatalError -eq $true){
Write-Host "Device is not ready to migrate. OS version is $($ver). Domain join status is $DSRegSatus. $c "
exit 99999
}else{
Write-Host "No Fatal Errors"
}


if($preflight -ge "5"){
Write-Host "Preflight check completed. Ready to go"
Write-Host "success" | Out-File C:\IT\Preflight-Ready-V3.txt

}else{
Write-Host "Device is not ready yet"
}




#---------------------------------------------------------------------------------------------------------------------Error Handeling-----------------------------------------------------------------------------------------------------------------


if($fatalError -ne $True){
Write-Host "No fatal errors script is successful"
$a = Get-date
Add-Content -Path C:\IT\TE-WS1-IntuneTaskInstall-Success-v36.log -Value "Success: $a"


}else{
Write-Host "ERROR: Something went wrong."


$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
$FileName = $env:COMPUTERNAME+$timestamp

$Log1 = Test-Path -Path "c:\temp\Create-Intune-Task-Log.txt"
$Log2 = Test-Path -Path "C:\IT\Intune-Preflight-Check.txt"

If($Log1 -eq $false -and $Log2 -eq $false){
Write-Host "Logs files don't exist"
exit 9999999

}


If($Log1 -eq $true -and $Log2 -eq $false){

Write-Host "Task install log present but Preflight isn't"

$compress = @{
  Path = "c:\temp\Create-Intune-Task-Log.txt"
  CompressionLevel = "Fastest"
  DestinationPath = "C:\IT\$filename.zip"
}
Compress-Archive @compress


}

If($Log1 -eq $false -and $Log2 -eq $true){

Write-Host "Task install log NOT present but Preflight is"

$compress = @{
  Path = "C:\IT\Intune-Preflight-Check.txt"
  CompressionLevel = "Fastest"
  DestinationPath = "C:\IT\$filename.zip"
}
Compress-Archive @compress


}

If($Log1 -eq $true -and $Log2 -eq $true){

Write-Host "Both Logs Present."

$compress = @{
  Path = "c:\temp\Create-Intune-Task-Log.txt", "C:\IT\Intune-Preflight-Check.txt"
  CompressionLevel = "Fastest"
  DestinationPath = "C:\IT\$filename.zip"
}
Compress-Archive @compress


}


try{
Write-Host "Going to attempt to copy logs up to Azure"
c:\IT\azcopy.exe copy "C:\IT\$filename.zip" "$AzureBlobURL"
$a = Get-date


}catch{

Write-Host "Error: Something went wrong during copy."
}
exit 9999999
}

Stop-Transcript