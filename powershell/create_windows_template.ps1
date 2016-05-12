#######################################################################
# File: create_windows_template.ps1
#
# Description:  This script configures Windows Guest OS which will be used
#               by VDNet later.
#
# Author: Yuanyou Yao
#
########################################################################

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
$ADMIN = 'Administrator'
$ADMIN_PASSWORD = 'ca\$hc0w'

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


function StopFreeSSHDService
{
    gecho "Checking service $sname"
    $sname = "FreeSSHDService"
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
}

function CheckIfCygwinInstalled
{
    gecho "Checking if Cygwin installed"
    if ((Test-Path $CYGWIN_LOCAL_PKT_DIR) -or
        (Test-Path $CYGWIN_ROOT_INSTALL_DIR)) {
        recho "Either $CYGWIN_LOCAL_PKT_DIR or $CYGWIN_ROOT_INSTALL_DIR exist."
        throw "Cygwin already installed"
    }
}

function InstallCygwinAndOpenssh
{
    gecho "Installing Cygwin"
    #if ('x' -ne 'x') {
    CheckIfCygwinInstalled
    StopFreeSSHDService
    $arch = GetOSArchitecture
    $installerURL = $CYGWIN_INSTALLERS_URLS[$arch]
    $localName = DownloadFile $installerURL
    $installArgs = "-D -L -s $CYGWIN_MIRROR -l $CYGWIN_LOCAL_PKT_DIR "
    $installArgs += "-R $CYGWIN_ROOT_INSTALL_DIR -P $PACKAGES -q"
    pecho "Setup Cygwin"
    Start-Process -FilePath $localName -ArgumentList "$installArgs" -Wait -PassThru
    #} else {
    $ssh_host_config_cmd = "$CYGWIN_ROOT_INSTALL_DIR\bin\bash.exe "
    $ssh_host_config_cmd += "--login -i -c "
    $ssh_host_config_cmd += "'/bin/ssh-host-config -y -w "
    $ssh_host_config_cmd += "$ADMIN_PASSWORD'"
    pecho "Configure Openssh: $ssh_host_config_cmd"
    Invoke-Expression "& $ssh_host_config_cmd"
    pecho "Start service $SSH_SERVICE_NAME"
    Start-Service -Name $SSH_SERVICE_NAME
    $serviceStatus = (Get-Service -Name $SSH_SERVICE_NAME).Status
    pecho "$SSH_SERVICE_NAME is $serviceStatus"
    if ($serviceStatus -ne 'Running') {
        recho "$SSH_SERVICE_NAME not working properly"
        throw "$SSH_SERVICE_NAME failed"
    }
    #}
}
#### MAIN ####
InstallCygwinAndOpenssh
gecho 'Done!'
