#!/bin/bash
# File:
#    preConfigure.sh
#
# Description:
#    This script is a standalone script specific to virtual devices upstream
#    testing. It does following,
#    1. create staf service
#    2. update staf configuration file
#    3. make perl 5.10 is compatible with staf
#    #4. correct the mount command output
#    After this script sueecssfully executed, the VM is ready for linux_auto_upstream.sh
#    !!!!This script can be only run once. Please start from scratch if need to run once more!!!!
#
# Prerequisites:
#     0. VM settings: 50G hard drive, 16G RAM, 8 CPUs, 1 e1000 Network Adapter
#     1. A. For SELS(vm name VD_UPSTREAM_SLES12_SP0_X64_HW11),
#           fresh install SELS12SP0 X86_64. ISO images location(NFS share),
#           exit15:/vol/vol0/home/ISO-Images/OS/Linux/SUSE/12/SP0/GM/SLE-12-Server-DVD-x86_64-GM-DVD1.iso
#           exit15:/vol/vol0/home/ISO-Images/OS/Linux/SUSE/12/SP0/GM/SLE-12-Server-DVD-x86_64-GM-DVD2.iso
#        B. For RHEL(vm name VD_UPSTREAM_RHEL7.2_SERVER_X64_HW11),
#           fresh install RHEL72SERVER X86_64. ISO images location(NFS share),
#           exit15:/vol/vol0/home/ISO-Images/OS/Linux/RedHatEnterpriseLinux/7/7.2/GA/rhel-server-7.2-x86_64-dvd.iso
#        Note:
#           The NFS mount point is
#           exit15:/vol/vol0/home/ISO-Images/OS
#     2. A. For SELS,
#           install gcc, ncurses-devel from
#           exit15:/vol/vol0/home/ISO-Images/OS/Linux/SUSE/12/SP0/GM/SLE-12-Server-DVD-x86_64-GM-DVD1.iso
#           with yast2.
#        B. For RHEL, ====> AUTOMATED
#           install ncurses-devel, openssl-devel, gcc from
#           exit15:/vol/vol0/home/ISO-Images/OS/Linux/RedHatEnterpriseLinux/7/7.2/GA/rhel-server-7.2-x86_64-dvd.iso
#           with rpm command. Below are commands,
#           B0. Mount the NFS share, mount the iso image, change directory
#               mount exit15:/vol/vol0/home/ISO-Images/OS /mnt
#               mkdir /iso
#               mount -o loop /mnt/Linux/RedHatEnterpriseLinux/7/7.2/GA/rhel-server-7.2-x86_64-dvd.iso /iso
#               cd /iso/Packages
#           B1. ncurses-devel
#               rpm -ivh ncurses-devel-5.9-13.20130511.el7.x86_64.rpm
#           B2. openssl-devel
#               rpm -ivh keyutils-libs-devel-1.5.8-3.el7.x86_64.rpm
#               rpm -ivh libcom_err-devel-1.42.9-7.el7.x86_64.rpm
#               rpm -ivh libverto-devel-0.2.5-4.el7.x86_64.rpm
#               rpm -ivh libsepol-devel-2.1.9-3.el7.x86_64.rpm
#               rpm -ivh pcre-devel-8.32-15.el7.x86_64.rpm
#               rpm -ivh pkgconfig-0.27.1-4.el7.x86_64.rpm
#               rpm -ivh libselinux-devel-2.2.2-6.el7.x86_64.rpm
#               rpm -ivh krb5-devel-1.13.2-10.el7.x86_64.rpm
#               rpm -ivh zlib-devel-1.2.7-15.el7.x86_64.rpm
#               rpm -ivh openssl-devel-1.0.1e-42.el7_1.9.x86_64.rpm
#           B3. gcc
#               rpm -ivh libmpc-1.0.1-3.el7.x86_64.rpm
#               rpm -ivh cpp-4.8.5-4.el7.x86_64.rpm
#               rpm -ivh kernel-headers-3.10.0-327.el7.x86_64.rpm
#               rpm -ivh glibc-headers-2.17-105.el7.x86_64.rpm
#               rpm -ivh glibc-devel-2.17-105.el7.x86_64.rpm
#               rpm -ivh gcc-4.8.5-4.el7.x86_64.rpm
#     3. install libopenssl-devel (*SELS only*) with yast2 from
#        w3-dbc301:/dbc/w3-dbc301/yuanyouy/sles12/SLE-12-SDK-DVD-x86_64-GM-DVD1.iso
#     4. enable ssh access with root. Execute below command, ====> AUTOMATED
#        sed -i -e 's/.*PermitRootLogin.*/PermitRootLogin=yes/g' /etc/ssh/sshd_config
#     5. A. For SELS,
#           stop and disable firewall. Execute below commands,
#           systemctl stop SuSEfirewall2.service
#           systemctl disable SuSEfirewall2.service
#           systemctl stop SuSEfirewall2_init.service
#           systemctl disable SuSEfirewall2_init.service
#        B. For SELS, ====> AUTOMATED
#           stop and disable firewall. Execute below commands,
#           systemctl stop firewalld.service
#           systemctl disable firewalld.service
#     6. install STAF 3.4.24 amd64 version. Download from official site,
#        https://sourceforge.net/settings/mirror_choices?projectname=staf&filename=staf/V3.4.24/STAF3424-setup-linux-amd64.bin
#        or internal server,
#        wget http://w3-dbc301.eng.vmware.com/yuanyouy/vd/upstream/STAF3424-setup-linux-amd64.bin
#     7. rename network interface name to old 'ethx'(*RHEL only*) ====> AUTOMATED
#        sed -i -e 's/\(GRUB_CMDLINE_LINUX.*\)"/\1 net.ifnames=0 biosdevname=0"/' /etc/default/grub
#        grub2-mkconfig -o /boot/grub2/grub.cfg
#        mv /etc/sysconfig/network-scripts/ifcfg-eno16777736 /etc/sysconfig/network-scripts/ifcfg-eth0
#        correct options in /etc/sysconfig/network-scripts/ifcfg-eth0 as below,
#            BOOTPROTO=dhcp
#            NAME=eth0
#            DEVICE=eth0
#            ONBOOT=yes
#
# Test Coverage:
#       A. SuSE Enterprise Linux Server 12 SP 0 X86_64
#       B. Red Hat Enterprise Linux Workstation release 7.2 (Maipo) X86_64
#
# Author: yuanyouy@vmware.com
#
# Change Log:
#     v0.1 - support SELS12 X86_64
#     v0.2 - support RHEL7.2 X86_64
#

#### global variables ####
#### global variables ####
current_os=
logs=()
log_index=1


#### global constants ####
STAF_BASE=/usr/local/staf
STAF_BIN=/usr/local/staf/bin
STAF_LIB=/usr/local/staf/lib
WORK_DIR=/root
LOG_LIST_FILE=${WORK_DIR}/loglistfile
SLES12_X64='SUSE Linux Enterprise Server 12'
RHEL72_X64='Red Hat Enterprise Linux Server release 7.2'
declare -a OS_LIST=(
   "${SLES12_X64}"
   "${RHEL72_X64}"
)
declare -a OS_ARCH=(
   x86_64
)
VERSION_FILES=(
    /etc/issue
    /etc/SuSE-release
    /etc/os-release
    /etc/redhat-release
)

#### functions ####
function _echo {
    color=$1
    msg=$2
    default=0
    case $color in
        red )
            echo -ne '\033[41;30m'
            ;;
        green )
            echo -ne '\033[42;30m'
            ;;
        yellow )
            echo -ne '\033[43;30m'
            ;;
        *)
            default=1
            ;;
    esac
    echo -n $msg
    if [[ $default -eq 0 ]]; then
        echo -e "\033[0m"
    fi
}
function recho { _echo red "$*"; }
function yecho { _echo yellow "$*"; }
function gecho { _echo green "$*"; }

# This function will save supported OS in variable current_os
function check_os {
    gecho 'Check supported operating system'
    for os in "${OS_LIST[@]}"
    do
        for file in "${VERSION_FILES[@]}"
        do
            if grep -w "$os" $file &>/dev/null; then
                echo "Found version $os in $file"
                current_os="$os"
                break
            fi
        done
    done
    if [[ -z $current_os ]]; then
        recho "Unsupported Operating System"
        exit 1
    else
        echo "The Operating System is $current_os"
    fi
    echo Current kernel version is $(uname -r)
}

function create_staf_service {
    gecho Create staf service
    local sd=/etc/systemd/system
    local sn=stafd.service
    local fpath=${sd}/${sn}
    if [[ ! -d $sd ]]; then
        recho No service directory $sd
        exit 1
    fi
    cat <<EOF >${fpath}
[Unit]
Description=STAF 3.4.24 amd64
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/staf/startSTAFProc.sh

[Install]
WantedBy=multi-user.target
EOF
    echo Staf service configuration file:
    cat ${fpath}
    echo Enable staf service
    systemctl enable $sn
    echo Check staf service status
    systemctl status $sn
}

function update_staf_config_file {
    gecho Update staf configuration file
    local fname=STAF.cfg
    local fpath=${STAF_BIN}/${fname}
    if [[ ! -s $fpath ]]; then
        recho No staf configuration file $fpath
        exit 1
    fi
    cat <<EOF >${fpath}
# Turn on tracing of internal errors and deprecated options
trace enable tracepoints "error deprecated"

# Enable TCP/IP connections
interface ssl library STAFTCP option Secure=Yes option Port=6550
interface tcp library STAFTCP option Secure=No  option Port=6500

# Set default local trust
trust machine *://* level 5

# Add default service loader
serviceloader library STAFDSLS
EOF
    echo Staf configuration file:
    cat ${fpath}
}

function update_perl_and_staf_compatibility {
    gecho Update perl and staf compatibility
    local mp=/bldmnt/toolchain
    local link=/build
    local toolchain=build-toolchain.eng.vmware.com:/toolchain
    local fstab=/etc/fstab
    local staf_extra=${STAF_BASE}/STAFExtra.sh
    local staf_env=${STAF_BASE}/STAFEnv.sh
    local log=${WORK_DIR}/mount_toolchain.log
    [[ ! -d $mp ]] && mkdir -p $mp
    [[ ! -h $link ]] && rm -rf $link && ln -s $(dirname $mp) $link

    echo Mount toolchain
    mount $toolchain $mp &>$log
    logs+=($log); ((log_index++))
    if [[ $? -ne 0 ]]; then
        recho Failed to mount toolchain from $toolchain to $mp
        exit 1
    fi
    echo Add toolchain to fstab
    echo "$toolchain $mp nfs ro 0 0" >>${fstab}

    echo Update staf extra configuration
    cat <<EOF >${staf_extra}
export LD_LIBRARY_PATH=/build/toolchain/lin64/perl-5.10.0/lib/5.10.0/x86_64-linux-thread-multi/CORE:$LD_LIBRARY_PATH
export PERLLIB=/usr/local/staf/bin:/usr/local/staf/lib/perl510:$PERLLIB
export PATH=/usr/local/staf/bin:/bldmnt/toolchain/lin64/perl-5.10.0/bin:$PATH
EOF
    echo Staf extra configuration file:
    cat ${staf_extra} 
    echo Import staf extra configurations
    sed -i -e '/STAFExtra/d' $staf_env
    sed -i -e "1 a\. ${staf_extra}" $staf_env
    echo Staf env file:
    cat ${staf_env}
}


function update_mount_output {
    gecho Update mount command output
    # see below mount output on RHEL7, two slashes
    # mount | grep automation
    # 10.115.172.226://vd_template_automation on /automation ...
    # To make it survive from VDNet, we need to remove one slash
    local mount_path=/usr/bin/mount
    local mount_backup=/usr/bin/mount.stock
    cp $mount_path $mount_backup
    chmod 4755 $mount_backup
    chmod 4755 $mount_path
    cat <<EOF >/usr/bin/mount
#!/bin/bash
if [[ \$# -eq 0 ]]; then
    $mount_backup | sed -e 's/\/\//\//g'
else
    $mount_backup "\$@"
fi
EOF
}

# RHEL only
function install_assistant_pkgs {
    gecho Install assistant packages needed by compiling kernel
    echo Mount NFS share to /mnt
    mount exit15:/vol/vol0/home/ISO-Images/OS /mnt
    echo Create directory /iso
    mkdir /iso
    echo Mount RHEL7.2 iso to /iso
    mount -o loop /mnt/Linux/RedHatEnterpriseLinux/7/7.2/GA/rhel-server-7.2-x86_64-dvd.iso /iso
    cd /iso/Packages
    echo Install ncurses-devel
    rpm -ivh ncurses-devel-5.9-13.20130511.el7.x86_64.rpm
    echo Install openssl-devel
    rpm -ivh keyutils-libs-devel-1.5.8-3.el7.x86_64.rpm
    rpm -ivh libcom_err-devel-1.42.9-7.el7.x86_64.rpm
    rpm -ivh libverto-devel-0.2.5-4.el7.x86_64.rpm
    rpm -ivh libsepol-devel-2.1.9-3.el7.x86_64.rpm
    rpm -ivh pcre-devel-8.32-15.el7.x86_64.rpm
    rpm -ivh pkgconfig-0.27.1-4.el7.x86_64.rpm
    rpm -ivh libselinux-devel-2.2.2-6.el7.x86_64.rpm
    rpm -ivh krb5-devel-1.13.2-10.el7.x86_64.rpm
    rpm -ivh zlib-devel-1.2.7-15.el7.x86_64.rpm
    rpm -ivh openssl-devel-1.0.1e-42.el7_1.9.x86_64.rpm
    echo Install gcc
    rpm -ivh libmpc-1.0.1-3.el7.x86_64.rpm
    rpm -ivh cpp-4.8.5-4.el7.x86_64.rpm
    rpm -ivh kernel-headers-3.10.0-327.el7.x86_64.rpm
    rpm -ivh glibc-headers-2.17-105.el7.x86_64.rpm
    rpm -ivh glibc-devel-2.17-105.el7.x86_64.rpm
    rpm -ivh gcc-4.8.5-4.el7.x86_64.rpm
    echo Umount RHEL7.2 iso from /iso
    cd ~
    umount /iso
    echo Remove directory /iso
    rm -rf /iso
}

# RHEL only
function rename_network_interface {
    gecho Rename network interfaces to the old ethxxx
    sed -i -e 's/\(GRUB_CMDLINE_LINUX.*\)"/\1 net.ifnames=0 biosdevname=0"/' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    mv /etc/sysconfig/network-scripts/ifcfg-eno* /etc/sysconfig/network-scripts/ifcfg-eth0
    sed -i -e 's/\^\(BOOTPROTO=\).*/\1dhcp/g;s/\^\(NAME=\).*/\1eth0/g;s/^\(DEVICE=\).*/\1eth0/g;s/^\(ONBOOT=\).*/\1yes/g' /etc/sysconfig/network-scripts/ifcfg-eth0
}

function disable_redhat_firewall {
    gecho Disable firewall
    systemctl stop firewalld.service
    systemctl disable firewalld.service
}

function enable_ssh_root_access {
    gecho Enable ssh root access
    sed -i -e 's/.*PermitRootLogin.*/PermitRootLogin=yes/g' /etc/ssh/sshd_config
}

function list_log_files {
    gecho List all log files
    echo "${logs[@]}"
    >$LOG_LIST_FILE
    for f in ${logs[@]}
    do
        echo $f >>$LOG_LIST_FILE
    done
}


#### MAIN ####
gecho Start - $(date)
check_os
create_staf_service
update_staf_config_file
update_perl_and_staf_compatibility
enable_ssh_root_access
#update_mount_output
if [[ $current_os = ${RHEL72_X64} ]]; then
    install_assistant_pkgs
    rename_network_interface
    disable_redhat_firewall
fi
list_log_files
gecho Done - $(date)
