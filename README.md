# WS1-to-Intune
Scripts that I wrote to migrate from WS1 to Intune

There is a Zip file you can upload directly to WS1. 

To migrate a device simply enterprise wipe the device with the keeps apps option.
The enterprise wipe will generate events on the PC that trigger scheduled tasks. The scheduled tasks will immediately enroll the device.
There is no impact to the end user.

If you want to upload the logs for troubleshooting you will need to grab a copy of AZCopy.exe https://github.com/Azure/azure-storage-azcopy
That will copy the logs to Azure Blob Storage.


GPUpdate-FixNetProfiles.ps1 isn't required but since I was moving to cert based network auth at the same time it helped me run GP update when I moved the PC object in AD to get the right GPO.
