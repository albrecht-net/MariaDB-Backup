#!/bin/bash

####################################################################################################
#                                                                                                  #
# Script Name         : backup-databases                                                           #
# Description         : Use this script to automate backups for a MariaDB database.                #
#                                                                                                  #
# Author              : Albrecht Jonas (https://github.com/albrecht-net/)                          #
#                                                                                                  #
# Usage               : backup-databases.sh [-f|-i]                                                #
#                           -f Create full backup                                                  #
#                           -i Create incremental backup                                           #
#                       To create a incremental backup, first a full backup, using the             #
#                       argument -f, must be successfully created.                                 #
#                                                                                                  #
# Before use          : The following variables must be set to a valid value:                      #
#                       BACKUP_DIR              Directory to place the temporary files.            #
#                                               Path without ending "/".                           #
#                       STORAGE_DEST            Directoy to which all finished backups will get    #
#                                               moved. Path without ending "/".                    #
#                       TARGET_NAME_PREFIX      String which will be used as prefix filename.      #
#                                                                                                  #
#                       Set the options in the mariabackup statement as needed according to:       #
#                       https://mariadb.com/kb/en/mariabackup-options/                             #
#                                                                                                  #
# Exit Codes          : 0 Successfull                                                              #
#                       2 Illegal usage of the script (missing or invalid argument)                #
#                       3 Directory with TARGET_NAME already exists. No backup was created.        #
#                       4 No base dir for incremental backup found. No incremental backup was      #
#                         created. (Not used if argument -f is set)                                #
#                       5 Failed to create backup. Problem occurred during execution of            #
#                         mariabackup.                                                             #
#                       6 Failed to copy files to STORAGE_DEST. Backup was created                 #
#                         anyways but not moved to STORAGE_DEST.                                   #
#                                                                                                  #
####################################################################################################

BACKUP_DIR=$(dirname $0)
STORAGE_DEST=/mnt/backup
TARGET_NAME_PREFIX=dbsrv-backup

function usage {
    echo "Usage: $0 [-f|-i]"
    echo "To open readme: 'head -36 $0'"
    exit 2
}

# Without valid environment variables show usage and exit
if [ -z ${BACKUP_DIR+x} ] || [ -z ${STORAGE_DEST+x} ] || [ -z ${TARGET_NAME_PREFIX+x} ]
then
    usage
fi

# Without valid input show usage and exit
if [ ${#} -eq 0 ]
then
    usage
fi

unset ACTION

# Define list of arguments expected in the input
optstring="fi"

while getopts ${optstring} arg;
do
    case ${arg} in
        f)
            if [ ${ACTION+x} ]
            then
                usage
            fi
            ACTION=FULL
            printf "Creating full database backup...\n"
            ;;
        i)
            if [ ${ACTION+x} ]
            then
                usage
            fi
            ACTION=INCREMENTAL
            printf "Creating incremental database backup...\n"
            ;;
        ?)
            usage
            ;;
    esac
done

cd ${BACKUP_DIR}

DATE=$(date +%Y-%m-%d-%H%M)
TARGET_NAME_FULL=${TARGET_NAME_PREFIX}_${DATE}.full
TARGET_NAME_INCREMENTAL=${TARGET_NAME_PREFIX}_${DATE}.inc
INCREMENTAL_BASE_DIR=$(find ./${TARGET_NAME_PREFIX}_*.full -maxdepth 0 -type d 2> /dev/null | sort -nr | head -n1)

case ${ACTION} in
    FULL)
        if [ -d ./${TARGET_NAME_FULL} ]
        then
            printf "Directory ${BACKUP_DIR}/${TARGET_NAME_FULL} already exists. No full backup was created!\n"
            exit 3
        fi

        mkdir -p ./${TARGET_NAME_FULL}

        printf "Start mariabackup utility...\n"

        START=$(date +%s)

        # Execute backup of db. Change options and credentials for mariabackup here
        mariabackup --backup \
            --target-dir=./${TARGET_NAME_FULL}/data/ \
            --host=127.0.0.1 \
            --port=3306 \
            --user=backup \
            >> ./${TARGET_NAME_FULL}/${TARGET_NAME_PREFIX}.log 2>&1

        BACKUP_RETURNSTATE=$?
        END=$(date +%s)

        printf "\n----------------------------------------\n\n" >> ./${TARGET_NAME_FULL}/${TARGET_NAME_PREFIX}.log
        printf "Execution date:      ${DATE}\n" >> ./${TARGET_NAME_FULL}/${TARGET_NAME_PREFIX}.log
        printf "Backup runtime:      $((END-START))s\n" >> ./${TARGET_NAME_FULL}/${TARGET_NAME_PREFIX}.log

        if [ ${BACKUP_RETURNSTATE} -ne 0 ]
        then
            printf "Failed to create full backup. Check ${BACKUP_DIR}/${TARGET_NAME_FULL}/${TARGET_NAME_PREFIX}.log\n"
            exit 5
        fi

        printf "Full backup created in: ${BACKUP_DIR}/${TARGET_NAME_FULL}\n"
        printf "Compressing files...\n"

        # Pack new backup files to .tar.gz
        tar -cpzf ${TARGET_NAME_FULL}.tar.gz ${TARGET_NAME_FULL}

        # Remove folders with full backup except newly created folder
        find ./${TARGET_NAME_PREFIX}_*.full -maxdepth 0 -type d -not -name ${TARGET_NAME_FULL} -exec rm -r {} \;

        printf "Tar-Archive created: ${BACKUP_DIR}/${TARGET_NAME_FULL}.tar.gz.\n"
        ;;
    INCREMENTAL)
        if [ -z ${INCREMENTAL_BASE_DIR} ] || [ ! -d ${INCREMENTAL_BASE_DIR} ]
        then
            printf "No base dir for incremental backup found\n"
            exit 4
        fi

        if [ -d ./${TARGET_NAME_INCREMENTAL} ]
        then
            printf "Directory ${BACKUP_DIR}/${TARGET_NAME_INCREMENTAL} already exists. No incremental backup was created!\n"
            exit 3
        fi

        mkdir -p ./${TARGET_NAME_INCREMENTAL}

        printf "Start mariabackup utility...\n"

        START=$(date +%s)

        # Execute backup of db. Change options and credentials for mariabackup here
        mariabackup --backup \
            --target-dir=./${TARGET_NAME_INCREMENTAL}/data/ \
            --incremental-basedir=${INCREMENTAL_BASE_DIR}/data/ \
            --host=127.0.0.1 \
            --port=3306 \
            --user=backup \
            >> ./${TARGET_NAME_INCREMENTAL}/${TARGET_NAME_PREFIX}.log 2>&1

        BACKUP_RETURNSTATE=$?
        END=$(date +%s)

        printf "\n----------------------------------------\n\n" >> ./${TARGET_NAME_INCREMENTAL}/${TARGET_NAME_PREFIX}.log
        printf "Execution date:      ${DATE}\n" >> ./${TARGET_NAME_INCREMENTAL}/${TARGET_NAME_PREFIX}.log
        printf "Backup runtime:      $((END-START))s\n" >> ./${TARGET_NAME_INCREMENTAL}/${TARGET_NAME_PREFIX}.log
        printf "Incremental basedir: `basename ${INCREMENTAL_BASE_DIR}`\n" >> ./${TARGET_NAME_INCREMENTAL}/${TARGET_NAME_PREFIX}.log

        if [ ${BACKUP_RETURNSTATE} -ne 0 ]
        then
            printf "Failed to create incremental backup. Check ${BACKUP_DIR}/${TARGET_NAME_INCREMENTAL}/${TARGET_NAME_PREFIX}.log\n"
            exit 5
        fi

        printf "Incremetal backup created in: ${BACKUP_DIR}/${TARGET_NAME_INCREMENTAL}\nBase dir used: ${INCREMENTAL_BASE_DIR}\n"
        printf "Compressing files...\n"

        # Pack new backup files to .tar.gz
        tar -cpzf ${TARGET_NAME_INCREMENTAL}.tar.gz ${TARGET_NAME_INCREMENTAL}

        # Remove folders with incremental backup
        find ./${TARGET_NAME_PREFIX}_*.inc -maxdepth 0 -type d -exec rm -r {} \;

        printf "Tar-Archive created: ./${TARGET_NAME_INCREMENTAL}.tar.gz and folder removed.\n"
        ;;
esac

# Copy all backuped files to remote location
# Files are defined in temporary .export file

printf "Move backups to storage destination...\n"

find ./${TARGET_NAME_PREFIX}_*.tar.gz -maxdepth 0 -type f | sort -nr > ./.export
rsync --times --protect-args --remove-source-files --files-from=./.export . ${STORAGE_DEST}

RSYNC_RETURNSTATE=$?

# Remove temporary .export file
rm ./.export

if [ ${RSYNC_RETURNSTATE} -ne 0 ]
then
    printf "Failed to move (some) backups to ${STORAGE_DEST}\n"
    exit 6
else
    printf "Backups moved to ${STORAGE_DEST}\n"
    exit 0
fi
