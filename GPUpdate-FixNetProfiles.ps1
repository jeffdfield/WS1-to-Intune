

Remove-Item c:\IT\Network.txt -Force
Start-Transcript -Path c:\IT\Network.txt
Remove-Item $env:TEMP\Network.txt -Force

do{
$datetime = get-date
$tickets = $false

netsh lan show profile *> $env:TEMP\Network.txt
$NetSH = get-content -path $env:TEMP\klist.txt
$NetSHTest = Select-String -Path "$env:TEMP\Network.txt" -Pattern 'Microsoft: Smart Card or other certificate'

if($NetSHTest -eq $null){

Write-Host "Wrong Wired Profile - $datetime"

try {
    Start-Process C:\Windows\System32\cmd.exe -ArgumentList ("/C", "gpupdate /force") -WindowStyle Hidden -PassThru -Wait
    $gpResult = [datetime]::FromFileTime(([Int64] ((Get-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}").startTimeHi) -shl 32) -bor ((Get-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}").startTimeLo))
    $lastGPUpdateDate = Get-Date ($gpResult[0])
    Write-Host "Last GPUpdate was $lastGPUpdateDate" 
    [int]$lastGPUpdateDays = (New-TimeSpan -Start $lastGPUpdateDate -End (Get-Date)).Days

    if ($lastGPUpdateDays -eq 0){        
        Write-Host "gpupdate completed successfully"            
        $GPUpdateStatus = $true
    }
    else{
        Write-Host "gpupdate failed"
        }
}
catch{
    $errMsg = $_.Exception.Message
    return $errMsg
    $GPUpdateStatus = $true
}

}else{
Write-Host "Group policy is updated. Machine has correct wired profile - $datetime"
$GPUpdateStatus = $true
Remove-Item $env:TEMP\Network.txt -Force
}

}until($GPUpdateStatus -eq $true)
Stop-Transcript
Remove-Item $env:TEMP\Network.txt -Force