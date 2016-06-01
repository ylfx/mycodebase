#!/bin/bash
# File: linux_auto_upstream.sh
#
# Description:
#     This script is specific to virtual devices upstream testing.
#     It does following things,
#     1. download kernel source code
#     2. compile, configure, install the new kernel
#
# Prerequisites:
#     preConfigure.sh must be run prior to this script.
#
# Test Coverage:
#       SuSE Enterprise Linux Server 12 SP 0 X86_64
#       Red Hat Enterprise Linux Workstation release 7.2
#
# Author: yuanyouy@vmware.com
#
# v0.1 - support SuSE Enterprise Linux Server 12 SP 0 X86_64
# v0.2 - support Red Hat Enterprise Linux Workstation release 7.2

#### global variables ####
current_os=
KERNEL_URL='http://w3-dbc301.eng.vmware.com/yuanyouy/vd/upstream/linux-4.5.tar.xz'
EXEC_MODE= # can be UPDATE, CHECK
KERNEL_VERSION=
logs=()


#### global constants ####
SUPPORTED_DRIVERS=(vmxnet3 e1000e)
MAX_IF_INDEX=9
JOBS=8
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
WORK_DIR=/vdupstream
BUILD_OUTPUT_DIR=${WORK_DIR}/kernel
KERNEL_CONFIG=${BUILD_OUTPUT_DIR}/.config
LOG_LIST_FILE=${WORK_DIR}/loglistfile
POWEROFF_FLAG='__NEEDPOWEROFF__'


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

# Only allow root to run the script
function check_root_user {
    gecho 'Check root privileges'
    userid=$(id -u)
    if [[ $userid -ne 0 ]]; then
        recho "Plese run the script with root user"
        exit 1
    fi
}

function check_working_directory {
    gecho 'Check working directory'
    [[ ! -d $WORK_DIR ]] && mkdir -p $WORK_DIR
    [[ ! -d $WORK_DIR ]] && recho "Failed to initialize working directory $WORK_DIR" && exit 1
    mkdir -p $BUILD_OUTPUT_DIR
}

# Current we only care about vmxnet3 and e1000e
function show_net_drivers {
    gecho Show network drivers information
    for d in ${SUPPORTED_DRIVERS[@]}
    do
        echo Show driver $d information:
        modinfo $d
        if lsmod | grep -w $d &>/dev/null; then
            echo Driver $d is loaded
        else
            echo Driver $d is not loaded
        fi
    done
}

function update_kernel {
    gecho Upgrade kernel
    echo Current kernel is $(uname -r)
    local download_log="$WORK_DIR/kernel_download.log"
    local kernel_filename=${KERNEL_URL##*/}
    local kernel_basename=${kernel_filename%.*} # remove .xz
    kernel_basename=${kernel_basename%.*} # remove .tar
    local save_to="${WORK_DIR}/${kernel_filename}"
    local untar_log="$WORK_DIR/kernel_decompress.log"
    echo Download kernel from $KERNEL_URL, save to $save_to
    if [[ ! -f $save_to || ! -s $save_to ]]; then
        if [[ $KERNEL_URL =~ ^https ]]; then
            wget --no-check-certificate -O $save_to $KERNEL_URL &>$download_log
        elif [[ $KERNEL_URL =~ ^http ]]; then
            wget -O $save_to $KERNEL_URL &>$download_log
        else
            recho Illegal kernel link
            exit 1
        fi
        if [[ $? -ne 0 ]]; then
            recho "Failed to download kernel from $tools_url"
            logs+=($download_log)
            exit 1
        fi
        logs+=($download_log)
        echo Kernel downloaded successfully
    else
        yecho $KERNEL_URL already download to $save_to
    fi
    echo Decompress kernel ball
    cd $WORK_DIR
    xzcat $kernel_filename | tar xvf - &>$untar_log
    if [[ $? -ne 0 ]]; then
        logs+=($untar_log)
        recho "Failed to decompress $kernel_filename"
        exit 1
    fi
    logs+=($untar_log)
    cd $kernel_basename
    echo Compile and install kernel
    local logto=
    local index=0
    for cmd in "make -j${JOBS} O=$BUILD_OUTPUT_DIR mrproper" \
               "make -j${JOBS} O=$BUILD_OUTPUT_DIR menuconfig" \
               "make -j${JOBS} O=$BUILD_OUTPUT_DIR" \
               "make -j${JOBS} O=$BUILD_OUTPUT_DIR modules_install install"
    do
        logto=$WORK_DIR/make.${index}.log
        ((index++))
        echo Execute command: $cmd
        date
        if echo $cmd | grep -w menuconfig &>/dev/null; then
            $cmd
        else
            $cmd &>$logto
        fi
        if [[ $? -ne 0 ]]; then
            logs+=($logto)
            recho Failed to execute $cmd
            exit 1
        fi
        logs+=($logto)
    done
    date
}

function update_mount_output {
    gecho Update mount command output
    # see below mount output on RHEL7, two slashes
    # mount | grep automation
    # 10.115.172.29://vd_template_automation on /automation ...
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

# For RHEL only
function update_ifconfig_output {
    gecho Update ifconfig command output
    # see below mount output on RHEL7+, there is a colon after network interface name,
    # ifconfig or ifconfig -a or ifconfig eth0
    # eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
    #         inet 10.116.249.51  netmask 255.255.240.0  broadcast 10.116.255.255
    #         inet6 fe80::20c:29ff:fe55:ef7e  prefixlen 64  scopeid 0x20<link>
    #         ether 00:0c:29:55:ef:7e  txqueuelen 1000  (Ethernet)
    #         RX packets 131044  bytes 100057617 (95.4 MiB)
    #         RX errors 0  dropped 0  overruns 0  frame 0
    #         TX packets 7021  bytes 906713 (885.4 KiB)
    #         TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
    #
    # lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
    #         inet 127.0.0.1  netmask 255.0.0.0
    #         inet6 ::1  prefixlen 128  scopeid 0x10<host>
    #         loop  txqueuelen 0  (Local Loopback)
    #         RX packets 12  bytes 912 (912.0 B)
    #         RX errors 0  dropped 0  overruns 0  frame 0
    #         TX packets 12  bytes 912 (912.0 B)
    #         TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
    # To make it survive from VDNet, we need to remove the colon
    local ifconfig_path=/usr/sbin/ifconfig
    local ifconfig_backup=/usr/sbin/ifconfig.stock
    cp $ifconfig_path $ifconfig_backup
    cat <<EOF >/usr/sbin/ifconfig
#!/bin/bash
$ifconfig_backup "\$@" | sed -e 's/^\([a-z0-9]*\):/\1/g'
EOF
}

# For RHEL7 only
function set_default_boot_entry
{
    gecho Set the new kernel as default boot entry
    grub2-set-default 0
}

# For Suse only
function check_suse_if_file {
    gecho 'Check network interface file'
    local if_dir=/etc/sysconfig/network
    local if_file=
    if [[ ! -d $if_dir ]]; then
        yecho "No $if_dir, skip"
        return
    fi
    for i in $(eval echo {0..$MAX_IF_INDEX})
    do
        if_file="${if_dir}/ifcfg-eth${i}"
        if [[ -f $if_file ]]; then
            yecho "$if_file exists, skip"
            continue
        fi
        echo Create $if_file
        cat <<EOF >${if_file}
STARTMODE='auto'
BOOTPROTO='dhcp'
EOF
    echo File content:
    cat $if_file
    done
}
# For Redhat only
function check_redhat_if_file {
    gecho 'Check network interface file'
    local if_dir=/etc/sysconfig/network-scripts/
    local if_file=
    if [[ ! -d $if_dir ]]; then
        yecho "No $if_dir, skip"
        return
    fi
    for i in $(eval echo {0..$MAX_IF_INDEX})
    do
        if_file="${if_dir}/ifcfg-eth${i}"
        if [[ -f $if_file ]]; then
            yecho "$if_file exists, skip"
            continue
        fi
        echo Create $if_file
        cat <<EOF >${if_file}
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
PEERDNS=yes
PEERROUTES=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_PEERDNS=yes
IPV6_PEERROUTES=yes
IPV6_FAILURE_FATAL=no
NAME=eth${i}
DEVICE=eth${i}
ONBOOT=yes
EOF
    echo File content:
    cat $if_file
    done
}

# For Redhat only
function disable_libvirtd
{
    gecho 'Disable libvirtd service'
    systemctl stop libvirtd.service
    systemctl disable libvirtd.service
}
function check_kernel {
    gecho Check kernel
    if [[ $KERNEL_VERSION = $(uname -r) ]]; then
        recho Failed to update kernel
        exit 1
    else
        gecho Successfully upgrade kernel from $KERNEL_VERSION to $(uname -r)
    fi
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
function write_poweroff_flag {
    gecho 'Need to Poweroff the system. After that it is ready for VDNet'
    echo $POWEROFF_FLAG
    #poweroff
}

function usage
{
    cat <<EOF
    This tool can run two modes: UPDATE and CHECK modes.
    UPDATE mode will update the kernel with given kernel URL.
    CHECK mode will check the kernel by comparing current kernel version with old kernel version.
    Note, make sure to *reboot* the system after UPDATE mode to make the new kernel take effect, after that one can run CHECK mode.
    $prog_name -h                               # Help message for this tool
    $prog_name -u <Kernel URL> [-m UPDATE]      # Execute UPDATE mode: Update kernel
    $prog_name -k <Kernel version> <-m CHECK>   # Execute CHECK mode: Check if kernel successfully updated
EOF
}

function process_args
{
    ARGS=$(getopt -o hu:m:k: -l "help,url:,mode:,kernel:" -n "$prog_name" -- "$@")
    if [ $? -ne 0 ]; then
        usage
        exit 1
    fi

    eval set -- "$ARGS"
    while true; do
        case "$1" in
            -h|--help)
                shift
                usage
                exit 1
                ;;
            -u|--url)
                shift
                if [[ -n $1 ]]; then
                    KERNEL_URL=$1
                    shift
                fi
                ;;
            -m|--mode)
                shift
                if [[ -n $1 ]]; then
                    EXEC_MODE=$1
                    shift
                fi
                ;;
            -k|--kernel)
                shift
                if [[ -n $1 ]]; then
                    KERNEL_VERSION=$1
                    shift
                fi
                ;;
            --)
                shift
                break
                ;;
        esac
    done

    if [[ $# -gt 0 ]]; then
        echo Unused arguments
        usage
        exit 1
    fi
}
#### MAIN ####
check_root_user
check_os
check_working_directory

prog_name=$(basename $0)
process_args "$@"

if [[ -z $EXEC_MODE ]]; then
    yecho "No execution mode given. Execute $prog_name in UPDATE mode by default"
    EXEC_MODE=UPDATE
else
    echo Execute $prog_name in $EXEC_MODE mode
fi
if [[ $EXEC_MODE = UPDATE ]]; then
    case $current_os in
        "${SLES12_X64}")
            show_net_drivers
            update_kernel
            update_mount_output
            check_suse_if_file
            ;;
        "${RHEL72_X64}")
            show_net_drivers
            update_kernel
            update_mount_output
            set_default_boot_entry
            check_redhat_if_file
            update_ifconfig_output
            disable_libvirtd
            ;;
        *)
            recho 'Unsupported Operating system.'
            exit 1
    esac
elif [[ $EXEC_MODE = CHECK ]]; then
    if [[ -z $KERNEL_VERSION ]]; then
        recho No kernel version given
        exit 1
    fi
    case $current_os in
        "${SLES12_X64}")
            show_net_drivers
            check_kernel
            ;;
        "${RHEL72_X64}")
            show_net_drivers
            check_kernel
            ;;
        *)
            recho 'Unsupported Operating system.'
            exit 1
    esac
else
    recho Unsupported mode
    usage
    exit 1
fi
list_log_files
[[ $EXEC_MODE = UPDATE ]] && write_poweroff_flag
