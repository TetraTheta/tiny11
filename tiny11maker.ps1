param(
  [switch] $CopyBin = $false,
  [switch] $CopyTweak = $false,
  [switch] $Debug = $false,
  [switch] $WimOnly = $false,
  [System.IO.FileInfo] $ScratchDisk = $env:SystemDrive
)

$ScriptVersion = "2024-08-26"

#region Helper Function
###################
# Helper Function #
###################
function ConvertTo-Boolean {
  param(
    [string]$Value
  )
  $Value = $Value.ToLower()

  switch ($Value) {
    "0" { return $false }
    "1" { return $true }
    "false"{ return $false }
    "n" { return $false }
    "no" { return $false }
    "ok" { return $true }
    "true" { return $true }
    "y" { return $true }
    "yes" { return $true }
    default { throw "Invalid input. Must be 'yes', 'no', 'y', 'n', 'true', 'false', '1', '0', or 'ok'." }
  }
}
function Format-Path {
  param(
    [string]$Path
  )
  $Path = $Path.Replace('/', '\').TrimEnd('\') # using single-quote for preventing interpretation
  if ($Path.Length -eq 1) {
    $Path += ':' # using single-quote for preventing interpretation
  }
  return $Path
}
function Write-InfoLike {
  param(
    [string]$Object,
    [string]$Header = "INFO",
    [switch]$NoNewline = $false
  )
  Write-Host -NoNewline -ForegroundColor Green "$Header "
  if ($NoNewline) {
    Write-Host $Object -NoNewline
  } else {
    Write-Host $Object
  }
}
function Write-WarnLike {
  param(
    [string]$Object,
    [string]$Header = "WARN",
    [switch]$NoNewline = $false
  )
  Write-Host -NoNewline -ForegroundColor Yellow "$Header "
  if ($NoNewline) {
    Write-Host $Object -NoNewline
  } else {
    Write-Host $Object
  }
}
function Write-ErrorLike {
  param(
    [string]$Object,
    [string]$Header = "ERROR",
    [switch]$NoNewline = $false
  )
  Write-Host -NoNewline -ForegroundColor Red "$Header "
  if ($NoNewline) {
    Write-Host $Object -NoNewline
  } else {
    Write-Host $Object
  }
}
#endregion Helper Function

# Enable debugging
if ($Debug) {
  Set-PSDebug -Trace 1
}

# Check validity of $ScratchDisk
try {
  $ScratchDisk = New-Object System.IO.FileInfo $ScratchDisk
  $ScratchDisk = Format-Path -Path $ScratchDisk
} catch {
  Write-ErrorLike "Invalid path provided for ScratchDisk: $ScratchDisk"
  exit 1
}

# Check if PowerShell execution is restricted
if ((Get-ExecutionPolicy) -eq "Restricted") {
  Write-WarnLike "Your current PowerShell Execution Policy is set to Restricted, which prevents scripts from running."
  $response = Read-Host "Do you want to change it to RemoteSigned? "
  try {
    $response = ConvertTo-Boolean -Value $response
    if ($response) {
      Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    } else {
      Write-ErrorLike "User refused to change PowerShell Execution Policy. Exiting..."
      exit 1
    }
  } catch {
    Write-ErrorLike "Cannot parse input to boolean value. Exiting..."
    exit 1
  }
}

# Check and run the script as admin if required
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-InfoLike "Restarting Tiny11 image creator as admin in a new window, you can close this one."
  $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";
  $newProcess.Arguments = $myInvocation.MyCommand.Definition;
  $newProcess.Verb = "runas";
  [System.Diagnostics.Process]::Start($newProcess);
  exit
}

# Start logging
Start-Transcript -Path "$PSScriptRoot\tiny11.log" 

# Configure window title
$Host.UI.RawUI.WindowTitle = "Tiny11 Image Creator"
Clear-Host

Write-InfoLike "Welcome to the tiny11 image creator! Release: " + $ScriptVersion

# Get $MediaDrive for copying Windows 11 image
New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny11\sources" | Out-Null
$MediaDrive = Read-Host "Please enter the drive letter for the Windows 11 image "
$MediaDrive = Format-Path -Path $MediaDrive

if ((Test-Path "$MediaDrive\sources\boot.wim") -eq $false -or (Test-Path "$MediaDrive\sources\install.wim") -eq $false) {
  if ((Test-Path "$MediaDrive\sources\install.esd") -eq $true) {
    Write-InfoLike "Found install.esd, converting to install.wim..."
    Start-Process -NoNewWindow -Wait -FilePath "dism" -ArgumentList "/English /Get-ImageInfo /ImageFile:$MediaDrive\sources\install.esd"
    $index = $null # temporary value
    do {
      $index = Read-Host "Please enter the image index to extract (default: 1) "
      if ($index -eq "") {
        $index = 1
      }
      $_isValid = [int]::TryParse($index, [ref]$parsedIndex)
      if (-not $_isValid -or $parsedIndex -lt 0) {
        Write-ErrorLike "Invalid input. Please enter a valid number >= 0."
      }
    } until ($_isValid -and $parsedIndex -ge 0)
    $index = $parsedIndex
    Write-InfoLike "Converting install.esd to install.wim. This may take a while..."
    Start-Process -NoNewWindow -Wait -FilePath "dism" -ArgumentList "/Export-Image /SourceImageFile:`"$MediaDrive\sources\install.esd`" /SourceIndex:$index /DestinationImageFile:`"$ScratchDisk\tiny11\sources\install.wim`" /Compress:max /CheckIntegrity"
  } else {
    Write-ErrorLike "Can't find Windows OS installation files in the specified Drive Letter."
    Write-ErrorLike "Please enter the correct DVD Drive Letter."
    exit
  }
}

$wimFilePath = "$ScratchDisk\tiny11\sources\install.wim"

Write-InfoLike "Copying Windows image..."
Copy-Item -Path "$MediaDrive\*" -Destination "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$ScratchDisk\tiny11\sources\install.esd" -Name IsReadOnly -Value $false | Out-Null
Remove-Item "$ScratchDisk\tiny11\sources\install.esd" | Out-Null
Write-InfoLike "Copy complete!"
Start-Sleep -Seconds 2
Clear-Host
Write-InfoLike "Getting image information:"
Start-Process -NoNewWindow -Wait -FilePath "dism" -ArgumentList "/English /Get-ImageInfo /ImageFile:$wimFilePath"
$index = $null # temporary value
do {
  $index = Read-Host "Please enter the image index (default: 1) "
  if ($index -eq "") {
    $index = 1
  }
  $_isValid = [int]::TryParse($index, [ref]$parsedIndex)
  if (-not $_isValid -or $parsedIndex -lt 0) {
    Write-ErrorLike "Invalid input. Please enter a valid number >= 0."
  }
} until ($_isValid -and $parsedIndex -ge 0)
Write-InfoLike "Mounting Windows image. This may take a while."

$wimFilePath = "$ScratchDisk\tiny11\sources\install.wim"
Start-Process -NoNewWindow -Wait -FilePath "takeown" -ArgumentList "/F $wimFilePath"
# TODO
Start-Process -NoNewWindow -Wait -FilePath "icacls" -ArgumentList "`"`""

& takeown "/F" $wimFilePath 
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
  Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
}
catch {
  # This block will catch the error and suppress it.
}
New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
& dism /English "/mount-image" "/imagefile:$($env:SystemDrive)\tiny11\sources\install.wim" "/index:$index" "/mountdir:$($env:SystemDrive)\scratchdir"

$imageIntl = & dism /English /Get-Intl "/Image:$($env:SystemDrive)\scratchdir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }

if ($languageLine) {
  $languageCode = $Matches[1]
  Write-InfoLike "Default system UI language code: $languageCode"
}
else {
  Write-InfoLike "Default system UI language code not found."
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($env:SystemDrive)\tiny11\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'

foreach ($line in $lines) {
  if ($line -like '*Architecture : *') {
    $architecture = $line -replace 'Architecture : ', ''
    # If the architecture is x64, replace it with amd64
    if ($architecture -eq 'x64') {
      $architecture = 'amd64'
    }
    Write-InfoLike "Architecture: $architecture"
    break
  }
}

if (-not $architecture) {
  Write-InfoLike "Architecture information not found."
}

Write-InfoLike "Mounting complete! Performing removal of applications..."

$packages = & 'dism' '/English' "/image:$($env:SystemDrive)\scratchdir" '/Get-ProvisionedAppxPackages' |
ForEach-Object {
  if ($_ -match 'PackageName : (.*)') {
    $matches[1]
  }
}
$packagePrefixes = 'Clipchamp.Clipchamp_', 'Microsoft.BingNews_', 'Microsoft.BingWeather_', 'Microsoft.GamingApp_', 'Microsoft.GetHelp_', 'Microsoft.Getstarted_', 'Microsoft.MicrosoftOfficeHub_', 'Microsoft.MicrosoftSolitaireCollection_', 'Microsoft.People_', 'Microsoft.PowerAutomateDesktop_', 'Microsoft.Todos_', 'Microsoft.WindowsAlarms_', 'microsoft.windowscommunicationsapps_', 'Microsoft.WindowsFeedbackHub_', 'Microsoft.WindowsMaps_', 'Microsoft.WindowsSoundRecorder_', 'Microsoft.Xbox.TCUI_', 'Microsoft.XboxGamingOverlay_', 'Microsoft.XboxGameOverlay_', 'Microsoft.XboxSpeechToTextOverlay_', 'Microsoft.YourPhone_', 'Microsoft.ZuneMusic_', 'Microsoft.ZuneVideo_', 'MicrosoftCorporationII.MicrosoftFamily_', 'MicrosoftCorporationII.QuickAssist_', 'MicrosoftTeams_', 'Microsoft.549981C3F5F10_'

$packagesToRemove = $packages | Where-Object {
  $packageName = $_
  $packagePrefixes -contains ($packagePrefixes | Where-Object { $packageName -like "$_*" })
}
foreach ($package in $packagesToRemove) {
  & 'dism' '/English' "/image:$($env:SystemDrive)\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}


Write-InfoLike "Removing Edge:"
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force >null
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force >null
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force >null
if ($architecture -eq 'amd64') {
  $folderPath = Get-ChildItem -Path "$ScratchDisk\scratchdir\Windows\WinSxS" -Filter "amd64_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName

  if ($folderPath) {
    & 'takeown' '/f' $folderPath '/r' >null
    & icacls $folderPath  "/grant" "$($adminGroup.Value):(F)" '/T' '/C' >null
    Remove-Item -Path $folderPath -Recurse -Force >null
  }
  else {
    Write-InfoLike "Folder not found."
  }
}
elseif ($architecture -eq 'arm64') {
  $folderPath = Get-ChildItem -Path "$ScratchDisk\scratchdir\Windows\WinSxS" -Filter "arm64_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName >null

  if ($folderPath) {
    & 'takeown' '/f' $folderPath '/r'>null
    & icacls $folderPath  "/grant" "$($adminGroup.Value):(F)" '/T' '/C' >null
    Remove-Item -Path $folderPath -Recurse -Force >null
  }
  else {
    Write-InfoLike "Folder not found."
  }
}
else {
  Write-InfoLike "Unknown architecture: $architecture"
}
& 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/r' >null
& 'icacls' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' >null
Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force >null
Write-InfoLike "Removing OneDrive:"
& 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" >null
& 'icacls' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' >null
Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" -Force >null
Write-InfoLike "Removal complete!"
Start-Sleep -Seconds 2
Clear-Host
Write-InfoLike "Loading registry..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS >null
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default >null
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat >null
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE >null
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM >null
Write-InfoLike "Bypassing system requirements(on the system image):"
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassCPUCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassRAMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassSecureBootCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassStorageCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassTPMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\MoSetup' '/v' 'AllowUpgradesWithUnsupportedTPMOrCPU' '/t' 'REG_DWORD' '/d' '1' '/f' >null
Write-InfoLike "Disabling Sponsored Apps:"
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'OemPreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SilentInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableWindowsConsumerFeatures' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'ContentDeliveryAllowed' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' '/v' 'ConfigureStartPins' '/t' 'REG_SZ' '/d' '{"pinnedList": [{}]}' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'ContentDeliveryAllowed' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'ContentDeliveryAllowed' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'FeatureManagementEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'OemPreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEverEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SilentInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SoftLandingEnabled' '/t' 'REG_DWORD' '/d' '0' '/f'>null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContentEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-310093Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338388Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338389Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338393Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-353694Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-353696Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContentEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SystemPaneSuggestionsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' '/v' 'DisablePushToInstall' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' '/v' 'DontOfferThroughWUAU' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'delete' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions' '/f' >null
& 'reg' 'delete' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps' '/f' >null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableConsumerAccountStateContent' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableCloudOptimizedContent' '/t' 'REG_DWORD' '/d' '1' '/f' >null
Write-InfoLike "Enabling Local Accounts on OOBE:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' '/v' 'BypassNRO' '/t' 'REG_DWORD' '/d' '1' '/f' >null
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\scratchdir\Windows\System32\Sysprep\autounattend.xml" -Force >null
Write-InfoLike "Disabling Reserved Storage:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' '/v' 'ShippedWithReserves' '/t' 'REG_DWORD' '/d' '0' '/f' >null
Write-InfoLike "Disabling Chat icon:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' '/v' 'ChatIcon' '/t' 'REG_DWORD' '/d' '3' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' '/v' 'TaskbarMn' '/t' 'REG_DWORD' '/d' '0' '/f' >null
Write-InfoLike "Removing Edge related registries"
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f >null
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f >null
Write-InfoLike "Disabling OneDrive folder backup"
& 'reg' 'add' "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" '/v' 'DisableFileSyncNGSC' '/t' 'REG_DWORD' '/d' '1' '/f' >null
Write-InfoLike "Disabling Telemetry:"
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' '/v' 'Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' '/v' 'TailoredExperiencesWithDiagnosticDataEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' '/v' 'HasAccepted' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' '/v' 'Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' '/v' 'RestrictImplicitInkCollection' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' '/v' 'RestrictImplicitTextCollection' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' '/v' 'HarvestContacts' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' '/v' 'AcceptedPrivacyPolicy' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' '/v' 'AllowTelemetry' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' '/v' 'Start' '/t' 'REG_DWORD' '/d' '4' '/f' >null
## this function allows PowerShell to take ownership of the Scheduled Tasks registry key from TrustedInstaller. Based on Jose Espitia's script.
function Enable-Privilege {
  param(
    [ValidateSet(
      "SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege", "SeBackupPrivilege",
      "SeChangeNotifyPrivilege", "SeCreateGlobalPrivilege", "SeCreatePagefilePrivilege",
      "SeCreatePermanentPrivilege", "SeCreateSymbolicLinkPrivilege", "SeCreateTokenPrivilege",
      "SeDebugPrivilege", "SeEnableDelegationPrivilege", "SeImpersonatePrivilege", "SeIncreaseBasePriorityPrivilege",
      "SeIncreaseQuotaPrivilege", "SeIncreaseWorkingSetPrivilege", "SeLoadDriverPrivilege",
      "SeLockMemoryPrivilege", "SeMachineAccountPrivilege", "SeManageVolumePrivilege",
      "SeProfileSingleProcessPrivilege", "SeRelabelPrivilege", "SeRemoteShutdownPrivilege",
      "SeRestorePrivilege", "SeSecurityPrivilege", "SeShutdownPrivilege", "SeSyncAgentPrivilege",
      "SeSystemEnvironmentPrivilege", "SeSystemProfilePrivilege", "SeSystemtimePrivilege",
      "SeTakeOwnershipPrivilege", "SeTcbPrivilege", "SeTimeZonePrivilege", "SeTrustedCredManAccessPrivilege",
      "SeUndockPrivilege", "SeUnsolicitedInputPrivilege")]
    $Privilege,
    ## The process on which to adjust the privilege. Defaults to the current process.
    $ProcessId = $pid,
    ## Switch to disable the privilege, rather than enable it.
    [Switch] $Disable
  )
  $definition = @'
 using System;
 using System.Runtime.InteropServices;
  
 public class AdjPriv
 {
  [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
  internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
   ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
  
  [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
  internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
  [DllImport("advapi32.dll", SetLastError = true)]
  internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
  [StructLayout(LayoutKind.Sequential, Pack = 1)]
  internal struct TokPriv1Luid
  {
   public int Count;
   public long Luid;
   public int Attr;
  }
  
  internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
  internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
  internal const int TOKEN_QUERY = 0x00000008;
  internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
  public static bool EnablePrivilege(long processHandle, string privilege, bool disable)
  {
   bool retVal;
   TokPriv1Luid tp;
   IntPtr hproc = new IntPtr(processHandle);
   IntPtr htok = IntPtr.Zero;
   retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
   tp.Count = 1;
   tp.Luid = 0;
   if(disable)
   {
    tp.Attr = SE_PRIVILEGE_DISABLED;
   }
   else
   {
    tp.Attr = SE_PRIVILEGE_ENABLED;
   }
   retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
   retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
   return retVal;
  }
 }
'@

  $processHandle = (Get-Process -id $ProcessId).Handle
  $type = Add-Type $definition -PassThru
  $type[0]::EnablePrivilege($processHandle, $Privilege, $Disable)
}

Enable-Privilege SeTakeOwnershipPrivilege

$regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks", [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
$regACL = $regKey.GetAccessControl()
$regACL.SetOwner($adminGroup)
$regKey.SetAccessControl($regACL)
$regKey.Close()
Write-InfoLike "Owner changed to Administrators."
$regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks", [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
$regACL = $regKey.GetAccessControl()
$regRule = New-Object System.Security.AccessControl.RegistryAccessRule ($adminGroup, "FullControl", "ContainerInherit", "None", "Allow")
$regACL.SetAccessRule($regRule)
$regKey.SetAccessControl($regACL)
Write-InfoLike "Permissions modified for Administrators group."
Write-InfoLike "Registry key permissions successfully updated."
$regKey.Close()

Write-InfoLike 'Deleting Application Compatibility Appraiser'
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{0600DD45-FAF2-4131-A006-0B17509B9F78}" /f >null
Write-InfoLike 'Deleting Customer Experience Improvement Program'
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{4738DE7A-BCC1-4E2D-B1B0-CADB044BFA81}" /f >null
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{6FAC31FA-4A85-4E64-BFD5-2154FF4594B3}" /f >null
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{FC931F16-B50A-472E-B061-B6F79A71EF59}" /f >null
Write-InfoLike 'Deleting Program Data Updater' 
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{0671EB05-7D95-4153-A32B-1426B9FE61DB}" /f >null
Write-InfoLike 'Deleting autochk proxy'
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{87BF85F4-2CE1-4160-96EA-52F554AA28A2}" /f >null
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{8A9C643C-3D74-4099-B6BD-9C6D170898B1}" /f >null
Write-InfoLike 'Deleting QueueReporting'
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{E3176A65-4E44-4ED3-AA73-3283660ACB9C}" /f >null
Write-InfoLike "Tweaking complete!"
Write-InfoLike "Unmounting Registry..."
$regKey.Close()
reg unload HKLM\zCOMPONENTS >null
reg unload HKLM\zDRIVERS >null
reg unload HKLM\zDEFAULT >null
reg unload HKLM\zNTUSER >null
reg unload HKLM\zSCHEMA >null
reg unload HKLM\zSOFTWARE
reg unload HKLM\zSYSTEM >null
Write-InfoLike "Cleaning up image..."
& 'dism' '/English' "/image:$ScratchDisk\scratchdir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' >null
Write-InfoLike "Cleanup complete."
Write-InfoLike ' '
Write-InfoLike "Unmounting image..."
& 'dism' '/English' '/unmount-image' "/mountdir:$ScratchDisk\scratchdir" '/commit'
Write-InfoLike "Exporting image..."
& 'dism' '/English' '/Export-Image' "/SourceImageFile:$ScratchDisk\tiny11\sources\install.wim" "/SourceIndex:$index" "/DestinationImageFile:$ScratchDisk\tiny11\sources\install2.wim" '/compress:recovery'
Remove-Item -Path "$ScratchDisk\tiny11\sources\install.wim" -Force >null
Rename-Item -Path "$ScratchDisk\tiny11\sources\install2.wim" -NewName "install.wim" >null
Write-InfoLike "Windows image completed. Continuing with boot.wim."
Start-Sleep -Seconds 2
Clear-Host
Write-InfoLike "Mounting boot image:"
$wimFilePath = "$($env:SystemDrive)\tiny11\sources\boot.wim" 
& takeown "/F" $wimFilePath >null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false
& 'dism' '/English' '/mount-image' "/imagefile:$ScratchDisk\tiny11\sources\boot.wim" '/index:2' "/mountdir:$ScratchDisk\scratchdir"
Write-InfoLike "Loading registry..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM
Write-InfoLike "Bypassing system requirements(on the setup image):"
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassCPUCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassRAMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassSecureBootCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassStorageCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassTPMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\MoSetup' '/v' 'AllowUpgradesWithUnsupportedTPMOrCPU' '/t' 'REG_DWORD' '/d' '1' '/f' >null
Write-InfoLike "Tweaking complete!"
Write-InfoLike "Unmounting Registry..."
$regKey.Close()
reg unload HKLM\zCOMPONENTS >null
reg unload HKLM\zDRIVERS >null
reg unload HKLM\zDEFAULT >null
reg unload HKLM\zNTUSER >null
reg unload HKLM\zSCHEMA >null
$regKey.Close()
reg unload HKLM\zSOFTWARE
reg unload HKLM\zSYSTEM >null
Write-InfoLike "Unmounting image..."
& 'dism' '/English' '/unmount-image' "/mountdir:$ScratchDisk\scratchdir" '/commit'
Clear-Host
Write-InfoLike "The tiny11 image is now completed. Proceeding with the making of the ISO..."
Write-InfoLike "Copying unattended file for bypassing MS account on OOBE..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\tiny11\autounattend.xml" -Force >null
Write-InfoLike "Creating ISO image..."
$hostArch = $Env:PROCESSOR_ARCHITECTURE
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArch\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
  Write-InfoLike "Will be using oscdimg.exe from system ADK."
  $OSCDIMG = "$ADKDepTools\oscdimg.exe"
}
else {
  Write-InfoLike "ADK folder not found. Will be using bundled oscdimg.exe."
    
  $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

  if (-not (Test-Path -Path $localOSCDIMGPath)) {
    Write-InfoLike "Downloading oscdimg.exe..."
    Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath

    if (Test-Path $localOSCDIMGPath) {
      Write-InfoLike "oscdimg.exe downloaded successfully."
    }
    else {
      Write-Error "Failed to download oscdimg.exe."
      exit 1
    }
  }
  else {
    Write-InfoLike "oscdimg.exe already exists locally."
  }

  $OSCDIMG = $localOSCDIMGPath
}

& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\tiny11\boot\etfsboot.com#pEF,e,b$ScratchDisk\tiny11\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny11" "$PSScriptRoot\tiny11.iso"

# Finishing up
Write-InfoLike "Creation completed! Press any key to exit the script..."
Read-Host "Press Enter to continue"
Write-InfoLike "Performing Cleanup..."
Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force >null
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force >null

# Stop the transcript
Stop-Transcript

exit
