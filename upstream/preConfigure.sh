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
#    #6. correct the mount command output
#    After this script sueecssfully executed, the VM is ready for linux_auto_upstream.sh
#    !!!!This script can be only run once. Please start from scratch if need to run once more!!!!
#
# Prerequisites:
#     0. VM settings: 50G hard drive, 16G RAM, 8 CPUs, 1 e1000 Network Adapter
#     1. fresh install SELS12SP0 X86_64. ISO images location(NFS share),
#        exit15:/vol/vol0/home/ISO-Images/OS/Linux/SUSE/12/SP0/GM/SLE-12-Server-DVD-x86_64-GM-DVD1.iso
#        exit15:/vol/vol0/home/ISO-Images/OS/Linux/SUSE/12/SP0/GM/SLE-12-Server-DVD-x86_64-GM-DVD2.iso
#     2. install gcc, ncurses-devel from
#        exit15:/vol/vol0/home/ISO-Images/OS/Linux/SUSE/12/SP0/GM/SLE-12-Server-DVD-x86_64-GM-DVD1.iso
#     3. install libopenssl-devel from
#        w3-dbc301:/dbc/w3-dbc301/yuanyouy/sles12/SLE-12-SDK-DVD-x86_64-GM-DVD1.iso
#     4. enable ssh access with root. Execute below command,
#        sed -i -e 's/.*PermitRootLogin.*/PermitRootLogin=yes/g' /etc/ssh/sshd_config
#     5. stop and disable firewall. Execute below commands,
#        systemctl stop SuSEfirewall2.service
#        systemctl disable SuSEfirewall2.service
#        systemctl stop SuSEfirewall2_init.service
#        systemctl disable SuSEfirewall2_init.service
#     6. install STAF 3.4.24 amd64 version. Download from official site,
#        https://sourceforge.net/settings/mirror_choices?projectname=staf&filename=staf/V3.4.24/STAF3424-setup-linux-amd64.bin
#        or internal server,
#        wget http://w3-dbc301.eng.vmware.com/yuanyouy/vd/upstream/STAF3424-setup-linux-amd64.bin
#
# Test Coverage:
#       SuSE Enterprise Linux Server 12 SP 0 X86_64
#
# Author: yuanyouy@vmware.com
#
# v0.1 base


#### global variables ####
logs=()
log_index=1


#### global constants ####
STAF_BASE=/usr/local/staf
STAF_BIN=/usr/local/staf/bin
STAF_LIB=/usr/local/staf/lib
WORK_DIR=/root
LOG_LIST_FILE=${WORK_DIR}/loglistfile

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
create_staf_service
update_staf_config_file
update_perl_and_staf_compatibility
#update_mount_output
list_log_files
gecho Done - $(date)
