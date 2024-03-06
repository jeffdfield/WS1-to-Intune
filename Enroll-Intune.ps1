<#
Created by: Jeffery Field (jfield)
Purpose: Checks for MDM Enrollment status and attempts to enroll into Intune if WS1

		:Change Log:
	1/20/23 - initial write
    6/20/23 - Added toast prompt for successful migration
#>

Start-Transcript -Path C:\Windows\Logs\Intune-Migration-Log.txt -Append
$VerbosePreference = "Continue"


#---------------------------------------------------------------------------------------------------------------------------------------------------------------------

function Search-Registry { 
<# 
.SYNOPSIS 
Searches registry key names, value names, and value data (limited). 

.DESCRIPTION 
This function can search registry key names, value names, and value data (in a limited fashion). It outputs custom objects that contain the key and the first match type (KeyName, ValueName, or ValueData). 

.EXAMPLE 
Search-Registry -Path HKLM:\SYSTEM\CurrentControlSet\Services\* -SearchRegex "svchost" -ValueData 

.EXAMPLE 
Search-Registry -Path HKLM:\SOFTWARE\Microsoft -Recurse -ValueNameRegex "ValueName1|ValueName2" -ValueDataRegex "ValueData" -KeyNameRegex "KeyNameToFind1|KeyNameToFind2" 

#> 
    [CmdletBinding()] 
    param( 
        [Parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)] 
        [Alias("PsPath")] 
        # Registry path to search 
        [string[]] $Path, 
        # Specifies whether or not all subkeys should also be searched 
        [switch] $Recurse, 
        [Parameter(ParameterSetName="SingleSearchString", Mandatory)] 
        # A regular expression that will be checked against key names, value names, and value data (depending on the specified switches) 
        [string] $SearchRegex, 
        [Parameter(ParameterSetName="SingleSearchString")] 
        # When the -SearchRegex parameter is used, this switch means that key names will be tested (if none of the three switches are used, keys will be tested) 
        [switch] $KeyName, 
        [Parameter(ParameterSetName="SingleSearchString")] 
        # When the -SearchRegex parameter is used, this switch means that the value names will be tested (if none of the three switches are used, value names will be tested) 
        [switch] $ValueName, 
        [Parameter(ParameterSetName="SingleSearchString")] 
        # When the -SearchRegex parameter is used, this switch means that the value data will be tested (if none of the three switches are used, value data will be tested) 
        [switch] $ValueData, 
        [Parameter(ParameterSetName="MultipleSearchStrings")] 
        # Specifies a regex that will be checked against key names only 
        [string] $KeyNameRegex, 
        [Parameter(ParameterSetName="MultipleSearchStrings")] 
        # Specifies a regex that will be checked against value names only 
        [string] $ValueNameRegex, 
        [Parameter(ParameterSetName="MultipleSearchStrings")] 
        # Specifies a regex that will be checked against value data only 
        [string] $ValueDataRegex 
    ) 

    begin { 
        switch ($PSCmdlet.ParameterSetName) { 
            SingleSearchString { 
                $NoSwitchesSpecified = -not ($PSBoundParameters.ContainsKey("KeyName") -or $PSBoundParameters.ContainsKey("ValueName") -or $PSBoundParameters.ContainsKey("ValueData")) 
                if ($KeyName -or $NoSwitchesSpecified) { $KeyNameRegex = $SearchRegex } 
                if ($ValueName -or $NoSwitchesSpecified) { $ValueNameRegex = $SearchRegex } 
                if ($ValueData -or $NoSwitchesSpecified) { $ValueDataRegex = $SearchRegex } 
            } 
            MultipleSearchStrings { 
                # No extra work needed 
            } 
        } 
    } 

    process { 
        foreach ($CurrentPath in $Path) { 
            Get-ChildItem $CurrentPath -Recurse:$Recurse |  
                ForEach-Object { 
                    $Key = $_ 

                    if ($KeyNameRegex) {  
                        Write-Verbose ("{0}: Checking KeyNamesRegex" -f $Key.Name)  

                        if ($Key.PSChildName -match $KeyNameRegex) {  
                            Write-Verbose "  -> Match found!" 
                            return [PSCustomObject] @{ 
                                Key = $Key 
                                Reason = "KeyName" 
                            } 
                        }  
                    } 

                    if ($ValueNameRegex) {  
                        Write-Verbose ("{0}: Checking ValueNamesRegex" -f $Key.Name) 

                        if ($Key.GetValueNames() -match $ValueNameRegex) {  
                            Write-Verbose "  -> Match found!" 
                            return [PSCustomObject] @{ 
                                Key = $Key 
                                Reason = "ValueName" 
                            } 
                        }  
                    } 

                    if ($ValueDataRegex) {  
                        Write-Verbose ("{0}: Checking ValueDataRegex" -f $Key.Name) 

                        if (($Key.GetValueNames() | % { $Key.GetValue($_) }) -match $ValueDataRegex) {  
                            Write-Verbose "  -> Match!" 
                            return [PSCustomObject] @{ 
                                Key = $Key 
                                Reason = "ValueData" 
                            } 
                        } 
                    } 
                } 
        } 
    } 
} 

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------



#---------------------------------------------------------------------------------------------------------------------------------------------------------------------


#Switch to the invocaton pat(where the script is on disk) so the cache of intune or WS1
$scriptpath = $MyInvocation.MyCommand.Path
$scriptname = $MyInvocation.MyCommand.name
$dir = Split-Path $scriptpath
#Set-Location $dir


Write-Host "Executing $scriptname"
Write-Host "Starting Intune Enrollment Script"

New-EventLog -source IT-Script -LogName Application -ErrorAction Continue -Verbose

$IntuneAddr = Search-Registry -Path HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\* -Recurse -SearchRegex "https://r.manage.microsoft.com"
$WS1Addr = Search-Registry -Path HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\* -Recurse -SearchRegex ".awmdm.com/deviceservices"

if($WS1Addr -ne $null){
    Write-Host "Device is still enrolled in WS1. Exiting"
    exit 0
}



if($IntuneAddr -ne $null){

    Write-Host "Device is enrolled into Intune"
    Write-EventLog -ComputerName "$env:computername" -LogName Application -Source "IT-Script" -EventID 1000 -Message "Device has migrated from WS1 successfully." -EntryType Information -Verbose
    Get-ScheduledTask -TaskName "Intune-Enrollment" -ErrorAction SilentlyContinue |  Unregister-ScheduledTask -Confirm:$false -Verbose
    Get-ScheduledTask -TaskName "Enroll-Intune-Now" -ErrorAction SilentlyContinue |  Unregister-ScheduledTask -Confirm:$false -Verbose
    Start-Sleep -Seconds 90
    Get-ScheduledTask -TaskName "MDM-Toast" -ErrorAction SilentlyContinue |  Unregister-ScheduledTask -Confirm:$false -Verbose
    exit 0

}else{

    Write-Host "Device isn't enrolled in any MDM. Attempting to enroll into Intune"

    $key = 'SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*'

    if($key -ne $null){
    $keyinfo = Get-Item "HKLM:\$key"
    $url = $keyinfo.name
    $url = $url.Split("\")[-1]
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\$url"

    New-ItemProperty -LiteralPath $path -Name 'MdmEnrollmentUrl' -Value 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' -PropertyType String -Force -ea SilentlyContinue;
    New-ItemProperty -LiteralPath $path  -Name 'MdmTermsOfUseUrl' -Value 'https://portal.manage.microsoft.com/TermsofUse.aspx' -PropertyType String -Force -ea SilentlyContinue;
    New-ItemProperty -LiteralPath $path -Name 'MdmComplianceUrl' -Value 'https://portal.manage.microsoft.com/?portalAction=Compliance' -PropertyType String -Force -ea SilentlyContinue;

    Start-Process -filepath C:\Windows\system32\deviceenroller.exe -argumentlist "/c","/AutoEnrollMDM" -Wait -NoNewWindow -Verbose

    Write-Host "Ran DeviceEnroller.exe. Will check enrollment status again."
    Write-EventLog -ComputerName "$env:computername" -LogName Application -Source "IT-Script" -EventID 1001 -Message "Device isn't managed by a MDM. Attempted to enroll. Will recheck." -EntryType Warning
    $a = Get-date
    Write-Host "WS1 Migration Attempted: $a"
    }else{
        Write-Host "Device does not have cloud domain join info in registry. Exiting"
        exit 0
        
    }
}

Stop-Transcript
