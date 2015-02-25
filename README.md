# automatic-backup-ec2

Automatic Backup with Snapshots with aws tools in perl

Use: backupmanager.pl  [ --backup [--instanceid=<instance_id>] [--type=<tipo>] ] [--lifecycle] [--listinstances] [--listbackups [--instanceid=<instance_id>] ]
	--backup        : Run backups/snapshots of all instances or one instance if paramater "--instanceid" presents
	--instanceid    : Specify instance (<instance_id>, for example i-12345678) in actions "backup" y "listbackup"
	--type          : Specify tag of type of backup. By default "AUTO". If you specify instanceid parameter by default "ONDEMAND"
	--lifecycle     : Run removing of old backups/snapshots 
	--listinstances : Show list of running instances
	--listbackups   : Show list of availables backups/snapshots for one instance


Script internal variables:

- HTTP_PROXY
- HTTPS_PROXY
- AWS_CONFIG_FILE
