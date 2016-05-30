#!/bin/bash
# File: update_testsuite.sh
#
# Description: This script update the testsuite for VD testing. It must
#              be run on MC.
#
# Author: yuanyouy@vmware.com
#

echo Please run the script on MC
TESTSUITE_NAME=${1:-upstream}
URL_PREFIX="https://engweb.vmware.com/~yuanyouy/vd/${TESTSUITE_NAME}"
FILE_LIST=filelist
CUR_DIR=$(pwd -P)
prog_name=$(basename $0)
LOG_FILE=${prog_name}.log

echo Current directory ${CUR_DIR}
echo Log saved at $LOG_FILE

wget --no-check-certificate -O $FILE_LIST ${URL_PREFIX}/${FILE_LIST} &>$LOG_FILE
if [[ $? -ne 0 ]]; then
    echo Failed to get file list
    exit 1
fi
for file in $(cat $FILE_LIST)
do
    if [[ -f $file ]]; then
        :
        # echo Moving old file to ${file}.old
        # mv $file ${file}.old
    fi
    echo Updating $file
    wget --no-check-certificate -O $file ${URL_PREFIX}/${file} &>>$LOG_FILE
    if [[ $? -ne 0 ]]; then
        echo Failed to update file $file
        exit 1
    fi
    chmod 755 $file
done

rm ${FILE_LIST}
echo Done
