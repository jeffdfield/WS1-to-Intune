<#
Created by: Jeffery Field (jfield)
Purpose: Pops a toast notication to the user

		:Change Log:
	5/15/23 - initial write
    9/20/23 - Added line to remove scheduled task so it only pops once.
#>


Start-Transcript -Path C:\Windows\Logs\Intune-Migration-Log.txt -Append

#=======================================================================================================================Variables you need to set

# Set these to the public hosted images
$LogoImageUri = "https://raw.githubusercontent.com/.png"
$HeroImageUri = "https://raw.githubusercontent.com/.jpg"
$LogoImage = "$env:TEMP\ToastLogoImage.png"
$HeroImage = "$env:TEMP\ToastHeroImage.png"

#URL for More info button. Set this to a FAQ on Sharepoint
$URL = "https://sharepoint.com/sites/"


#Code you want to run if a user dismisses the toast.
$Dismiss = ""

#==============================================================================================================================================================================================================================================

function Display-ToastNotification() {
    $Load = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $Load = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    # Load the notification into the required format
    $ToastXML = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
    $ToastXML.LoadXml($Toast.OuterXml)
        
    # Display the toast notification
    try {
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($App).Show($ToastXml)
    }
    catch { 
        Write-Output -Message 'Something went wrong when displaying the toast notification' -Level Warn
        Write-Output -Message 'Make sure the script is running as the logged on user' -Level Warn     
    }
}


#Fetching images from uri
Invoke-WebRequest -Uri $LogoImageUri -OutFile $LogoImage
Invoke-WebRequest -Uri $HeroImageUri -OutFile $HeroImage

#Defining the Toast notification settings
#ToastNotification Settings
$Scenario = 'reminder' # <!-- Possible values are: reminder | short | long -->
        
# Load Toast Notification text
$AttributionText = "IT Notification"
$HeaderText = "Device Management Migration"
$TitleText = "Your device has finished the migration."
$BodyText1 = "To install software, use company portal in your start menu."
$BodyText2 = "If you experience issues please call the service desk and mention the migration"


# Check for required entries in registry for when using Powershell as application for the toast
# Register the AppID in the registry for use with the Action Center, if required
$RegPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
$App =  '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

# Creating registry entries if they don't exists
if (-NOT(Test-Path -Path "$RegPath\$App")) {
    New-Item -Path "$RegPath\$App" -Force
    New-ItemProperty -Path "$RegPath\$App" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD'
}

# Make sure the app used with the action center is enabled
if ((Get-ItemProperty -Path "$RegPath\$App" -Name 'ShowInActionCenter' -ErrorAction SilentlyContinue).ShowInActionCenter -ne '1') {
    New-ItemProperty -Path "$RegPath\$App" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD' -Force
}


#=======================================================================================================================XML for the toast


# Formatting the toast notification XML
[xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true" >$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$URL" content="Learn More" />
        <action activationType="system" arguments="$Dismiss" content="Dismiss"/>
    </actions>
</toast>
"@


#=======================================================================================================================Run the function to pop the toast notification


#Send the notification
$toast = Display-ToastNotification


#======================================================================================================================= Delete the toast task so it only pops once.

$taskname="MDM-Toast"
# delete existing task if it exists
Get-ScheduledTask -TaskName $taskname -ErrorAction SilentlyContinue |  Unregister-ScheduledTask -Confirm:$false


Stop-Transcript