#######################################################################
# File: create_windows_template.ps1
#
# Description: This script configures Windows Guest OS which will be used
#              by VDNet later.
#
# Test Coverage:
#     Good:
#     111117-Win-Server2008-Sp1-64-R2-Datacenter-Tools
#     111118-Win-Server2008-Sp1-64-R2-Datacenter-NoTools
#     111326-Windows-Server2012-R2U3-64-DataCenter-NoTools
#     111328-Windows-Server2012-64-DataCenter-NoTools
#     111310-Windows-10-64-Enterprise-NoTools
#     111308-Windows-10-32-Enterprise-NoTools
#     111189-Windows-7-SP1-Enterprise-ToolsTeam
#     Bad:
#              
# Version: 0.1
# Author: yuanyouy@vmware.com
#
########################################################################


#
# Command line arguments
#
param (
)


#
# Constants
#
$WORK_DIR = 'C:'
$CYGWIN_INSTALLERS_URLS =  @{
    '64-bit'='https://cygwin.com/setup-x86_64.exe';
    '32-bit'='https://cygwin.com/setup-x86.exe';
}
$CYGWIN_MIRROR = 'http://cygwin.mirror.constant.com'
$CYGWIN_LOCAL_PKT_DIR = "$WORK_DIR\cygwinpkts"
$CYGWIN_ROOT_INSTALL_DIR = "$WORK_DIR\cygwin"
$PACKAGES = "openssh"
$SSH_SERVICE_NAME = 'sshd'
$ADMIN_USER = 'Administrator'
$ADMIN_PASSWORD = 'ca\$hc0w'
$ADMIN_PASSWORD1 = 'ca$hc0w'


# Global variables
$final = $true # Indicate the final result of this script


#
# Helper functions
#
function recho($msg) {
    Write-Host -ForegroundColor Red "$msg"
}

function yecho($msg) {
    Write-Host -ForegroundColor Yellow "$msg"
}

function gecho($msg) {
    Write-Host -ForegroundColor Green "$msg"
}

function pecho($msg) {
    Write-Host "$msg"
}

function GetOSArchitecture
{
    gecho "Getting OS Architecture"
    $arch = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture
    return $arch
}

$initial = 0
function step($prompt) {
    $msg =  "`n" + (++$script:initial).toString() + ". $prompt"
    gecho "$msg"
}

function DownloadFile($url)
{
    gecho "Downloading file from $url"
    $webClient = New-Object Net.WebClient
    $name = $url -replace '.*/',''
    if ($name.length -eq 0) {
        throw "Failed to get the name from $url"
    }
    $localName ="$WORK_DIR\$name"
    $WebClient.DownloadFile($url, $localName)
    if (-not (Test-Path $localName)) {
        throw "Failed to download $name from $url to $localName"
    }
    return $localName
}

function CheckAdministratorPrivileges()
{
    step "Check Administrator Privileges"
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principalObj = New-Object System.Security.Principal.WindowsPrincipal($id)
    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    if ($principalObj.IsInRole($adminRole)) {
        pecho "Administrator privileges enabled"
    } else {
        throw "Administrator privileges disabled"
    }
}

function ConfigureExecutionPolicy()
{
    # Before execute the script, please modify the execution policy of
    # powershell as below
    Set-ExecutionPolicy ByPass -Force
}

function ConfigureStrictMode()
{
    Set-StrictMode -Version 2
}

function CheckWorkDir()
{
    step "Check work directory"
    if (-not (Test-Path $WORK_DIR)) {
        yecho "Work directory $WORK_DIR not existing, create it"
        New-Item -path $WORK_DIR -ItemType directory
    } else {
        gecho "Work directory $WORK_DIR already exists"
    }
}

function UpdateAdministratorPassword()
{
    step "Update password of Administrator"
    pecho "Set Administrator password to $ADMIN_PASSWORD1"
    $admin = [ADSI]"WinNT://./Administrator"
    # Once SetPassword failed, it will throw exception
    $admin.SetPassword($ADMIN_PASSWORD1)
}

function CheckPerlMatchSTAF()
{
    step 'Check if Perl matches STAF'
    try
    {
        $o = Get-Command staf -ErrorAction Stop
    }
    catch
    {
        throw 'No STAF found'
    }
    $staf_path = $o."Definition"
    $stafBinPath = $o | Split-Path
    $stafBase = Split-Path $stafBinPath
    pecho "STAF installed at $stafBase"

    try
    {
        $o = Get-Command perl -ErrorAction Stop
    }
    catch
    {
        throw "No perl found"
        # TODO: we assume perl installed on the system. We should install perl
        # by ourself if it do not exist in future.
    }
    $perl_path = $o."Definition"
    $perl_version = $o."FileVersionInfo"."FileVersion"
    $stafRequiredPerllibVersion = $s -replace '^(\d),(\d+),.*$', 'perl$1$2'
    pecho "Perl $perl_version installed at $perl_path"

    pecho 'Check the required STAF perllib'
    $stafRequiredPerllibPath = "$stafBinPath\$stafRequiredPerllibVersion"
    if (-not (Test-Path $stafRequiredPerllibPath)) {
        recho "$stafRequiredPerllibPath not found"
        throw 'Perl do not match STAF'
    }

    pecho 'Set environment variable PERLLIB'
    $o = [Environment]::GetEnvironmentVariable('PERLLIB', 'user')
    if ($o) {
        gecho "PERLIB already set: $o, skip"
    } else {
        [Environment]::SetEnvironmentVariable('PERLLIB',
            "$stafBinPath;$stafRequiredPerllibPath",'user')
    }
    $o = [Environment]::GetEnvironmentVariable('PERLLIB', 'user')
    if ($o) {
        gecho "PERLIB set successfully: ${o}"
    } else {
        throw 'Failed to set PERLLIB'
    }
}

function GetWin32OSObject
{
    $obj = Get-WmiObject -Class Win32_OperatingSystem
    return $obj
}

function StartScript($obj)
{
    $d = date
    gecho "`nSTART at $d ++++++++++++++++++++++++++++++++++++++++++++++++++++"
    $caption = $obj.Caption
    $h = hostname
    $user = $Env:Username
    $arch = $obj.OSArchitecture
    pecho "The script is running on $h ($caption $arch) with user $user`n"
    if ($user -ne $ADMIN_USER) {
        throw "Please run this script with $ADMIN_USER"
    }
}

function StopScript($finalResult)
{
    $d = date
    gecho "STOP at $d +++++++++++++++++++++++++++++++++++++++++++++++++++++`n"
    if ($finalResult -eq $true) {
        gecho 'Final Result: SUCCEEDED'
    } else {
        recho 'Final Result: FAILED'
    }
    Exit
}

function GetOSCaption()
{
    return (Get-WmiObject -Class Win32_OperatingSystem).Caption
}

function CheckPath($p)
{
    if (Test-Path $p) {
        pecho "Path $p existing, continue"
    } else {
        throw "Path $p not existing, please double check then retry. Aborting"
    }
}

function CheckVMwareTools()
{
    step "Check VMware Tools"
    $tools = Get-WmiObject -Class Win32_Product -Filter "Name='VMware Tools'"
    if ($tools) {
        $version = $tools.Version
        pecho "VMware Tools $version installed on the system"
    } else {
        yecho "No VMware Tools on the system"
        $installCmd = "D:"
        $toolsURL = $false # TODO: ChangeMe
        if ($toolsURL) {
            pecho "Download VMware Tools from $toolsURL"
            $localName = DownloadFile $toolsURL
            pecho "Start to install $localName"
            pecho 'Mount VMWare-Tools ISO file'
            $mountResult = Mount-DiskImage -ImagePath $localName -PassThru
            $driveLetter = ($mountResult | Get-Volume).DriveLetter
            if (-not $driveLetter) {
               throw 'Failed to get drive letter'
            }
            $o = Get-DiskImage -ImagePath $localName
            pecho "Info of ${localName}: $o"
            $installCmd = "${driveLetter}:"
        } else {
            pecho "Install VMWare Tools from CDROM"
            Read-Host -Prompt "Please insert CDROM then press any key to continue"
            sleep 5
        }
        $procName = 'setup'
        # if ([environment]::Is64BitOperatingSystem) { # Not work on win2008 sp1 64 r2
        $arch = GetOSArchitecture
        if ($arch -eq '64-bit') {
            $installCmd += "\setup64.exe"
            $procName += '64'
        } else {
            $installCmd += "\setup.exe"
        }
        $installArgs = "/S /v `"/qn /l*v `"`"$WORK_DIR\vmtoolsmsi.log`"" +
                       "`" REBOOT=R ADDLOCAL=ALL`""
        pecho "Start Installation with command: ${installCmd}"
        pecho "Start Installation with arguments: ${installArgs}"
        $process_info = Start-Process -FilePath $installCmd `
            -ArgumentList "$installArgs" -Wait -PassThru
        do
        {
            pecho 'Installation in progress...'
            sleep 5
            $o = Get-Process -Name $procName -ErrorAction SilentlyContinue
        }
        while ($o)
        pecho 'Installation Done'
        if ($toolsURL) {
            pecho 'UMount VMWare-Tools ISO file'
            Dismount-DiskImage -ImagePath $localName
        }
    }
    sleep 4
}

function EnableRDP()
{
    step "Enable Remote Desktop"
    $path = 'HKLM:\system\CurrentControlSet\Control\Terminal Server'
    CheckPath $path
    Set-ItemProperty -Path $path -Name fDenyTSConnections -Value 0
    Get-ItemProperty -Path $path  | Select fDenyTSConnections
}

function ConfigureFirewall()
{
    step "Configure Windows Firewall"
    $svc = "MpsSvc"
    Stop-Service -Name $svc -Force
    Set-Service -Name $svc -StartupType Disabled
    Get-Service -Name $svc
    sleep 1
}

function ConfigurePCA()
{
    step "Configure Program Compatibility Assistant Service"
    $svc = "PcaSvc"
    Stop-Service -Name $svc -Force
    Set-Service -Name $svc -StartupType Disabled
    Get-Service -Name $svc
    sleep 1
}

function ConfigureUAC()
{
    step "Configure User Account Control"
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    if (!(Test-Path $path)) {
        yecho "$path not existing, create it"
        New-Item -Path $path
    }
    Set-ItemProperty -Path $path -Name EnableLUA -Value 0
    Get-ItemProperty -Path $path  | Select EnableLUA
}

function ConfigureEventTracker()
{
    step "Configure Event Tracker"
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability'
    if (!(Test-Path $path)) {
        yecho "$path not existing, create it"
        New-Item -Path $path
    }
    Set-ItemProperty -Path $path -Name ShutdownReasonUI -Value 0
    Get-ItemProperty -Path $path  | Select ShutdownReasonUI
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability'
    if (!(Test-Path $path)) {
        yecho "$path not existing, create it"
        New-Item -Path $path
    }
    Set-ItemProperty -Path $path -Name ShutdownReasonUI -Value 0
    Set-ItemProperty -Path $path -Name ShutdownReason -Value 0
    Get-ItemProperty -Path $path  | Select ShutdownReasonUI, ShutdownReason
}

function ConfigureWindowsAutoUpdate()
{
    step "Configure Windows Automatic Update"
    $svc = "wuauserv"
    Stop-Service -Name $svc -Force
    Set-Service -Name $svc -StartupType Disabled
    Get-Service -Name $svc
    sleep 1
}

function DisableCtrlAltDelete()
{
    step "DisableCAD"
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    CheckPath $path
    Set-ItemProperty -Path $path -Name  disablecad -Value 1
    Get-ItemProperty -Path $path  | Select disablecad
    sleep 1
}

function ConfigureLowRiskFileTypes()
{
    step "Configure low risk file types"
    $path = 'HKCU:\Software\Microsoft\Windows' +
            '\CurrentVersion\Policies\Associations'
    if (!(Test-Path $path)) {
        yecho "$path not existing, create it"
        New-Item -Path $path
    }
    CheckPath $path
    #New-Item -Path $path
    Set-ItemProperty -Path $path -Name LowRiskFileTypes `
        -Value ".exe;.pl;.py;ps1"
    Get-ItemProperty -Path $path | Select LowRiskFileTypes
    sleep 1
}

function ConfigureAdministratorAutoLogon()
{
    step "Configure Administrator auto logon"
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    CheckPath $path
    Set-ItemProperty -Path $path -Name AutoAdminLogon -Value 1
    Set-ItemProperty -Path $path -Name DefaultUserName -Value Administrator
    #Set-ItemProperty -Path $path -Name DefaultPassword -Value 'B1gd3m0z'
    Set-ItemProperty -Path $path -Name DefaultPassword `
        -Value "$ADMIN_PASSWORD1"
    Get-ItemProperty -Path $path | 
        Select AutoAdminLogon, DefaultUserName, DefaultPassword
}

function ConfigureWindowsActivation()
{
    step "Postpone Windows Activation"
    # https://letitknow.wordpress.com/2012/08/01/
    # postponing-auto-activation-on-windows-server-2008-n-
    # expand-trial-time-period/
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' +
            '\SoftwareProtectionPlatform\Activation'
    CheckPath $path
    Set-ItemProperty -Path $path -Name Manual -Value 1
    Set-ItemProperty -Path $path  -Name NotificationDisabled -Value 1
    Get-ItemProperty -Path $path | Select Manual, NotificationDisabled
    Start-Job -Name SLMGR -ScriptBlock { slmgr -rearm }
    sleep 1
}

function PromptToRebootSystem()
{
    step "Please Reboot the system to make changes take effect"
    pecho "reboot command: shutdown /f /r /t 0"
    pecho $poweroff_flag
}

# Windows 10 only
function EnableAdministratorOpenEdgeOnWin10()
{
    step "Enable Administrator to open Edge"
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    CheckPath $path
    Set-ItemProperty -Path $path -Name FilterAdministratorToken -Value 1
    Get-ItemProperty -Path $path | Select FilterAdministratorToken
}

function StopPreinstalledSSHService()
{
    gecho "Checking preinstalled SSH services"
    $services = @{
        'FreeSSHDService'='FreeSSHDService.exe'; # Win2012 64 dc, Win7 sp1 64 en
        'OpenSSHd'='NoExisting.exe' # win2008 sp1 64 r2 dc
    }
    $startupDir = [System.Environment]::GetFolderPath('Startup')
    yecho "Found following stuffs under ${startupDir}:"
    Get-ChildItem -Path $startupDir | %{ yecho $_.Name}
    $services.GetEnumerator() | ForEach-Object {
        $sname = $_.Key
        $service = Get-Service -Name $sname -ErrorAction SilentlyContinue
        if ($service) {
            yecho "Found service $sname on the system."
            pecho "Stopping service $sname"
            Stop-Service -Name $sname
            pecho "Disabling service $sname"
            Set-Service -Name $sname -StartupType Disabled
        } else {
            gecho "No service $sname found on the system."
        }
        $proc = Get-Process -Name $sname -ErrorAction silentlycontinue
        if ($proc) {
            yecho "Found process $sname is running, stopping it"
            Stop-Process -Name $sname -Force -ErrorAction SilentlyContinue
        }
        $sbinary = $_.Value
        $sbinaryPath = "$startupDir\$sbinary"
        if (Test-Path $sbinaryPath) {
            yecho "Found Startup entry, removing $sbinaryPath"
            Remove-Item -Path $sbinaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function CheckIfCygwinInstalled()
{
    gecho "Checking if Cygwin installed"
    if ((Test-Path $CYGWIN_LOCAL_PKT_DIR) -or
        (Test-Path $CYGWIN_ROOT_INSTALL_DIR)) {
        yecho "Either $CYGWIN_LOCAL_PKT_DIR or $CYGWIN_ROOT_INSTALL_DIR exist"
        yecho "Cygwin already installed"
        return $true
    }
    return $false
}

function CheckIfOpensshConfigured()
{
    # This is just a sanity check.
    gecho "Checking if Openssh configured"
    $USERS_FOR_OPENSSH = @('sshd', 'cyg_server')
    $ret = $true
    for ($i=0; $i -lt $USERS_FOR_OPENSSH.length; $i++) {
        $user = $USERS_FOR_OPENSSH[$i]
        $o = net user $user 2>$null
        if (-not $o) {
            yecho "No user $user found"
            $ret = $false
        } else {
            yecho "User $user found"
        }
    }
    if ($ret) {
        yecho 'Openssh already configured'
    }
    return $ret
}

function InstallCygwin()
{
    step "Install Cygwin, configure Openssh"
    StopPreinstalledSSHService
    $ret =  CheckIfCygwinInstalled
    if (-not $ret) {
        $arch = GetOSArchitecture
        $installerURL = $CYGWIN_INSTALLERS_URLS[$arch]
        $localName = DownloadFile $installerURL
        $installArgs = "-D -L -s $CYGWIN_MIRROR -l $CYGWIN_LOCAL_PKT_DIR "
        $installArgs += "-R $CYGWIN_ROOT_INSTALL_DIR -P $PACKAGES -q"
        pecho "Setup Cygwin"
        Start-Process -FilePath $localName -ArgumentList "$installArgs" `
            -Wait -PassThru
    }
    $ret =  CheckIfOpensshConfigured
    if (-not $ret) {
        $ssh_host_config_cmd = "$CYGWIN_ROOT_INSTALL_DIR\bin\bash.exe "
        $ssh_host_config_cmd += "--login -i -c "
        $ssh_host_config_cmd += "'/bin/ssh-host-config -y -w "
        $ssh_host_config_cmd += "$ADMIN_PASSWORD'"
        pecho "Configure Openssh with command: $ssh_host_config_cmd"
        Invoke-Expression "& $ssh_host_config_cmd"
    }
    pecho "Start service $SSH_SERVICE_NAME"
    $serviceStatus = (Get-Service -Name $SSH_SERVICE_NAME).Status
    if ($serviceStatus -ne 'Running') {
        pecho "Starting..."
        Start-Service -Name $SSH_SERVICE_NAME
        $serviceStatus = (Get-Service -Name $SSH_SERVICE_NAME).Status
    }
    pecho "$SSH_SERVICE_NAME is $serviceStatus"
    if ($serviceStatus -ne 'Running') {
        recho "$SSH_SERVICE_NAME not working properly"
        throw "$SSH_SERVICE_NAME failed"
    }
    $bannerFile = "$CYGWIN_ROOT_INSTALL_DIR/etc/motd"
    if (-not (Test-Path $bannerFile)) {
        $welcomMsg = "`nWelcome to VDNet Cygwin Paradise!`n" + 
                     "               - Yuanyou"
        Out-File -FilePath $bannerFile -InputObject $welcomMsg
    }
}

# Windows 2008
function Win2008R2SP1DatacenterEdition()
{
    CheckWorkDir
    CheckAdministratorPrivileges
    ConfigureExecutionPolicy
    ConfigureStrictMode
    UpdateAdministratorPassword
    ConfigureAdministratorAutoLogon
    CheckVMwareTools
    CheckPerlMatchSTAF
    EnableRDP
    ConfigureFirewall
    ConfigureWindowsAutoUpdate
    DisableCtrlAltDelete
    ConfigureLowRiskFileTypes    
    InstallCygwin
    ConfigureWindowsActivation

    PromptToRebootSystem
}

# Windows 2012
function Win2012R2U3DatecenterEdition()
{
    Win2008R2SP1DatacenterEdition
}

# Windows 10
function Win10EnterpriseEdition()
{
    CheckWorkDir
    CheckAdministratorPrivileges
    ConfigureExecutionPolicy
    ConfigureStrictMode
    UpdateAdministratorPassword
    ConfigureAdministratorAutoLogon
    CheckVMwareTools
    CheckPerlMatchSTAF
    EnableRDP
    ConfigureFirewall
    ConfigureWindowsAutoUpdate
    DisableCtrlAltDelete
    ConfigureLowRiskFileTypes    
    InstallCygwin
    ConfigureWindowsActivation

    ConfigurePCA
    ConfigureEventTracker
    ConfigureUAC
    EnableAdministratorOpenEdgeOnWin10

    PromptToRebootSystem
}

# Windows 7
function Win7EnterpriseEdition()
{
    Win2008R2SP1DatacenterEdition
}

# Windows XP
function WinXP()
{
    Win2008R2SP1DatacenterEdition
}

# Windows 2016 Technical Preview 3
function Win2016TechnicalPreview()
{
    Win2008R2SP1DatacenterEdition
}


################################
############ MAIN ##############
################################

$OS_DICT = @{
    "Microsoft Windows Server 2008 R2 Datacenter"='Win2008R2SP1DatacenterEdition';
    "Microsoft Windows Server 2012 R2 Datacenter"='Win2012R2U3DatecenterEdition';
    "Microsoft Windows 10 Enterprise"='Win10EnterpriseEdition';
    "Microsoft Windows 7 Enterprise"='Win7EnterpriseEdition';
    "Microsoft Windows Server 2012 Datacenter"='Win2012R2U3DatecenterEdition';
    "Microsoft Windows Server 2016 Technical Preview 3"='Win2016TechnicalPreview';
    "Microsoft Windows XP Professional"='WinXP';
}

try
{
    $OSObj = GetWin32OSObject
    StartScript $OSObj
    $caption = $OSobj.Caption
    $caption = $caption.Trim()
    if ($OS_DICT[$caption]) {
        & $OS_DICT[$caption]
    } else {
        throw "Unsupport Operating System"
    }
}
catch
{
    $final = $false
    recho "Caught below exception:["
    $_ | Format-List -Force
    recho "]`n"
}
finally
{
    StopScript $final
}
