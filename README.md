# Database backup using mariabackup and systemd
## About
This script is used to create backups of a MariaDB database server. Using the mariabackup utility, it can create full and incremental backups, which then get moved as a tar archive to a choosen destination.

## Notes before setup
- The backup destination (*/mnt/backup* as default) can be any possible folder. As is, this folder is a remote samba share, therefore the cifs-utils will get installed. This could easily changed to a other protocol or a local mounted folder (other configuration methods are not described in this readme).
- The script will get executed from the same user as the database server (mysql as default).
 
## Setup
### Basic steps
- Install mariabackup[^1], rsync on your database server.
- Clone this repository and change directory to it.
- Create directories, move files and set permissions:
```
sudo mkdir -p /var/opt/dbsrv-backup
sudo mv ./var/opt/dbsrv-backup/dbsrv-backup.sh /var/opt/dbsrv-backup/dbsrv-backup.sh
sudo chown -R mysql:mysql /var/opt/dbsrv-backup
sudo chmod 0544 /var/opt/dbsrv-backup/dbsrv-backup.sh
sudo mv ./etc/systemd/systemd/dbsrv-backup* /etc/systemd/systemd/
sudo mkdir /mnt/backup
sudo chown mysql:mysql /mnt/backup
```
- Create a user on your database server and grant the following privileges[^2] to all databases if you have MariaDB >v10.5: RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR. You should only allow the user logon from localhost.
- Change the mariabackup options in */var/opt/dbsrv-backup/dbsrv-backup.sh* on line 112, 163. Set the --user and add, if you set a password to your backup user, the --password parameter [^3].

### Additional steps if using a samba remote backup destination
- Install cifs-utils
- Move files and set permissions:
```
sudo mv ./etc/systemd/systemd/mnt-backup* /etc/systemd/systemd/
sudo mv ./root/.smbcredentials /root/.smbcredentials
sudo chmod 0400 /root/.smbcredentials
```
- Edit */root/.smbcredentials* and set the correct samba credentials.
- Edit */etc/systemd/systemd/mnt-backup.mount* and set the remote path in the option *What=*.
- Edit */etc/systemd/systemd/mnt-backup.mount* and set the *uid* and *gid* to one of the user mysql in the option *Options=*
- Enable the automount feature for the remote backup destination: `sudo systemctl enable mnt-backup.automount`
- Test automount of directory */mnt/backup* (list of files in remote directory): `ls /mnt/backup`

### First test
- Run the first full backup:
`sudo -u mysql /var/opt/dbsrv-backup/dbsrv-backup.sh -f`
- Check if the exit code is 0: `echo $?`
- Check the mariabackup log (*/var/opt/dbsrv-backup/dbsrv-backup_YYYY-mm-dd-HHMM.full/dbsrv-backup.log*) if it completed successfully. This logfile can also be found in */mnt/backup/dbsrv-backup_YYYY-mm-dd-HHMM.inc.tar.gz*.
- Run the first incremental backup:
`sudo -u mysql /var/opt/dbsrv-backup/dbsrv-backup.sh -i`
- Check if the exit code is 0: `echo $?`
- Check the mariabackup log if it completed successfully. This logfile can be found in */mnt/backup/dbsrv-backup_YYYY-mm-dd-HHMM.inc.tar.gz*.

## Create backup
### Enable and start services in systemd
- Reload systemd with `sudo systemctl daemon-reload`
- Enable the timers: `sudo systemctl enable dbsrv-backup@f.timer` and `sudo systemctl enable dbsrv-backup@i.timer`
- Check if the units are loaded (not enabled): `systemctl status dbsrv-backup@f` and `systemctl status dbsrv-backup@i`
- Run again the full backup, this time with systemd, and then check the output in the journal: `sudo systemctl start dbsrv-backup@f` and `sudo journalctl -u backup@f.service`.
- Run again the incremental backup, this time with systemd, and then check the output in the journal: `sudo systemctl start dbsrv-backup@i` and `sudo journalctl -u backup@i.service`.

### Customize backup schedule
- Edit the options[^4] in */etc/systemd/systemd/dbsrv-backup@f.timer* and */etc/systemd/systemd/dbsrv-backup@i.timer* as needed.
- Reload systemd with `sudo systemctl daemon-reload`.
- Confirm next execution time with `systemctl list-timers`.

## Restore backup
1. Choose the backup archive in */mnt/backup/* with the timestamp you want to restore and copy it to a temporary folder.
2. Change directory to the temporary folder.
3. Untar the archive: `tar-xzf /dbsrv-backup_YYYY-mm-dd-HHMM.[full/inc].tar.gz`
4. If the choosen archive is a incremental backup, proceed with step 5, otherwise with step 7.
5. Search the entry of the choosen archive in the *./backup-databases.log* and look up which base dir was used at *Base dir used: [...]*
6. Copy the mentioned full backup archive to the same folder as in step 1 and untar the with `tar-xzf /dbsrv-backup_YYYY-mm-dd-HHMM.full.tar.gz`.
7. First prepare the full backup with `mariabackup --prepare --target=./dbsrv-backup_YYYY-mm-dd-HHMM.full/data/`.
8. If needed, prepare the incremental backup with `mariabackup --prepare --target=./dbsrv-backup_YYYY-mm-dd-HHMM.full/data/ --incremental-dir=./dbsrv-backup_YYYY-mm-dd-HHMM.inc/data/` to update the base (full) backup with the deltas of the incremental backup[^5].
9. If the database is still running, stop the MariaDB server process.
10. Copy the prepared data back to the mariadb datadir executing `mariabackup --copy-back --target=./dbsrv-backup_YYYY-mm-dd-HHMM.full.full/data/`[^6].
11. Fix the file permissions with `chown -R mysql:mysql /var/lib/mysql/`.
12. Finally start the MariaDB server process.
13. The created folder for the restoring procedure can be deleted.

***

[^1]: [Installing mariabackup](https://mariadb.com/kb/en/mariabackup-overview/#installing-on-linux) \
[^2]: MariaDB kb: [Authentication and Privileges](https://mariadb.com/kb/en/mariabackup-overview/#authentication-and-privileges) \
[^3]: MariaDB kb: [--password](https://mariadb.com/kb/en/mariabackup-options/#-p-password) \
[^4]: Manpage [systemd.timer(5)](https://manpages.debian.org/bullseye/systemd/systemd.timer.5) and [systemd.time(7)](https://manpages.debian.org/bullseye/manpages-de/systemd.time.7) \
[^5]: MariaDB kb: [Preparing the backup](https://mariadb.com/kb/en/incremental-backup-and-restore-with-mariabackup/#preparing-the-backup) \
[^6]: MariaDB kb: [Restoring the Backup](https://mariadb.com/kb/en/incremental-backup-and-restore-with-mariabackup/#restoring-the-backup) \