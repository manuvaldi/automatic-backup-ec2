#!/usr/bin/perl

use JSON; 
use Data::Dumper;
use POSIX qw(strftime);
use Date::Parse; 
use Getopt::Long;

# Configuration
	my $debuglevel=1;
	my $backupprefix="AutoBackup";
	my $mindaysfromcreation=1;
	my $lifecyclemaxdays=7;
	my $lifecyclemaxweeks=12; # 12 semanas

# Enviroment Variables
	$ENV{'PATH'}="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
	$ENV{'HTTP_PROXY'}="";
	$ENV{'HTTPS_PROXY'}="";
	$ENV{'AWS_CONFIG_FILE'}="./config";

# Variables
	my ($dobackup,$dolifecycle,$dolistinstances,$dolistbackups,$instanceid,$backuptype,$force);
	my @wday = qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/;

GetOptions( 	"backup" => \$dobackup,
		"lifecycle" => \$dolifecycle,
		"listinstances" => \$dolistinstances,
		"listbackups" => \$dolistbackups,
		"instanceid=s" => \$instanceid,
		"type=s" => \$backuptype,
		"force" => \$force
	);

logtext(0,"Start Script Backup/Snapshops AWS");

if ( $dobackup ) {

	logtext(0,"Performing Backup of instances' volumes");

	if ( !$backuptype ) {
		if ( $instanceid ) {
			$backuptype="ONDEMAND";
		} else {
			$backuptype="AUTO";
		}
	} 
	# Get Instance(s)
	my $instances_text;
	if ( $instanceid ) {
		$instances_text=getinstances($instanceid);
	} else {
		$instances_text=getinstances();
	}
	my $instances_json=decode_json($instances_text);
	
	foreach my $instance (@{$instances_json->{'Reservations'}}) {
		my $instance=$instance->{'Instances'}[0];
	
		# TAG
		my $instance_tags=$instance->{Tags};
		my $instance_name;
		foreach my $tag (@$instance_tags) {
			if ($tag->{Key} eq "Name" ) {
				$instance_name=$tag->{Value};
				last;
			}
		}
	
		# Instance
		my $instance_id=$instance->{InstanceId};
		
		# Creation Date
		my $instance_creationtime=$instance->{LaunchTime};
		my $instance_creationtimestamp=str2time($instance_creationtime);

		logtext(0,"BACKUP: ".$instance_name." - ".$instance_id);
		if ( (time() - $instance_creationtimestamp) > (60*60*24*$mindaysfromcreation) || $force) { # if match min days active
			# Volumes
			for my $vol (@{$instance->{BlockDeviceMappings}}) {
				logtext(0,"  VOLUME: ".$vol->{Ebs}->{VolumeId});
				my $prefix="";
				if (defined($backupprefix)){
					$prefix="$backupprefix -";
				} else {
					$prefix="Backup -";
				}
				my $cmd="aws ec2 create-snapshot  --volume-id ".$vol->{Ebs}->{VolumeId}." ";
				   $cmd.=" --description \"$prefix $instance_name - $instance_id - Vol:".$vol->{Ebs}->{VolumeId}." - $backuptype - ".strftime("%F %X",localtime)." (".time().")\"";
				logtext(10,"   Command: $cmd");
				my $salida=`$cmd`;
				my $snap=decode_json($salida);
				if ( defined ($snap->{'SnapshotId'}) ) {
					createtag($snap->{'SnapshotId'},"Server","$instance_name");
				}
			}
		} else {
			logtext(0,"Not to backup!!. Not enough min days from creation date ($mindaysfromcreation)");
		}
	}

}

if ( $dolifecycle ) {

	logtext(0,"Removing old backups  ( >$lifecyclemaxdays days and sundays > $lifecyclemaxweeks semanas ) ");

	# Get Snapshots
	my $snapshots_text=`aws ec2 describe-snapshots --owner-ids self`;
	my $snapshots=decode_json($snapshots_text);

	for $snap (@{$snapshots->{Snapshots}}) {
		if ( $snap->{Description} =~ /^$backupprefix\s.*\s\(\d+\)/ ) {
			logtext(0,"DESCRIPCION : ".$snap->{Description});
			logtext(0,"ID          : ".$snap->{SnapshotId});
			logtext(0,"FECHA       : ".$snap->{StartTime}." (".(time()-str2time($snap->{StartTime})).")");
			logtext(0,"WEEKDAY     : ". $wday[(localtime(str2time($snap->{StartTime})))[6] -1]." (".(localtime(str2time($snap->{StartTime})))[6].")");
			if (  (time()-str2time($snap->{StartTime})) > ($lifecyclemaxdays*24*60*60) ) {
				if (  (localtime(str2time($snap->{StartTime})))[6] == 0 && (time()-str2time($snap->{StartTime})) < ($lifecyclemaxweeks*24*60*60*7) ) {
					logtext(0," Backup valid of sunday. Nothing to do");
				} else {
					logtext(0," Removing backup");
					my $cmd="aws ec2 delete-snapshot  --snapshot-id $snap->{SnapshotId}";
					logtext(10,"   Command: $cmd");
					logtext(0,`$cmd 2>&1`."\n");
				}
			} else {
				logtext(0," Backup valid. Nothing to do");
			}
		}
	}

}

if ( $dolistinstances ) {

	my $instances_json=decode_json(getinstances());
        foreach my $instance (@{$instances_json->{'Reservations'}}) {
                my $instance=$instance->{'Instances'}[0];
		
		# TAG
		my $instance_tags=$instance->{Tags};
		my $instance_name;
		foreach my $tag (@$instance_tags) {
			if ($tag->{Key} eq "Name" ) {
				$instance_name=$tag->{Value};
				last;
			}
		}
	
		# Instance
		my $instance_id=$instance->{InstanceId};

		# IPs	
		my $instance_ips_hash;
		my $instance_net=$instance->{NetworkInterfaces};
		foreach my $interface (@$instance_net) {
			$instance_ips_hash->{$interface->{PrivateIpAddress}}=1;
			$instance_ips_hash->{$interface->{Association}->{PublicIp}}=1;
			$instance_ips_hash->{$interface->{PrivateIpAddresses}[0]->{PrivateIpAddress}}=1;
			$instance_ips_hash->{$interface->{PrivateIpAddresses}[0]->{Association}->{PublicIp}}=1;
		}
		my $instance_ips=",";
		foreach my $ipkey (keys $instance_ips_hash) {
			$instance_ips.=$ipkey.",";
		}
		$instance_ips =~ s/,+$//;
		$instance_ips =~ s/^,+//;
		$instance_ips =~ s/,+/ /;
		
		logtext(0,sprintf("    * %-25s   %-10s   %s",$instance_name,$instance_id,$instance_ips));	
	}
		
}


if ( $dolistbackups ) {

	my $instances_json=decode_json(getinstances($instanceid));
        foreach my $instance (@{$instances_json->{'Reservations'}}) {
                my $instance=$instance->{'Instances'}[0];
		
		# TAG
		my $instance_tags=$instance->{Tags};
		my $instance_name;
		foreach my $tag (@$instance_tags) {
			if ($tag->{Key} eq "Name" ) {
				$instance_name=$tag->{Value};
				last;
			}
		}
	
		# Instance
		my $instance_id=$instance->{InstanceId};

		# IPs	
		my $instance_ips_hash;
		my $instance_net=$instance->{NetworkInterfaces};
		foreach my $interface (@$instance_net) {
			$instance_ips_hash->{$interface->{PrivateIpAddress}}=1;
			$instance_ips_hash->{$interface->{Association}->{PublicIp}}=1;
			$instance_ips_hash->{$interface->{PrivateIpAddresses}[0]->{PrivateIpAddress}}=1;
			$instance_ips_hash->{$interface->{PrivateIpAddresses}[0]->{Association}->{PublicIp}}=1;
		}
		my $instance_ips=",";
		foreach my $ipkey (keys $instance_ips_hash) {
			$instance_ips.=$ipkey.",";
		}
		$instance_ips =~ s/,+$//;
		$instance_ips =~ s/^,+//;
		$instance_ips =~ s/,+/ /;
		
		logtext(0,sprintf(" INSTANCE:  %-25s   %-10s   %s",$instance_name,$instance_id,$instance_ips));	

		# Get Snapshots
		my $snapshots_text=`aws ec2 describe-snapshots --owner-ids self`;
		my $snapshots=decode_json($snapshots_text);
	
		my $totalsize=0;
		for $snap (@{$snapshots->{Snapshots}}) {
			if ( $snap->{Description} =~ /^$backupprefix\s-\s$instance_name\s-\s.*\s\(\d+\)/ ) {
				logtext(0,sprintf("     * %s (%s GB) [%s - %s] --> %s --> %s",$snap->{SnapshotId},$snap->{VolumeSize},$snap->{State},$snap->{Progress},$snap->{Description},$snap->{StartTime}));
				$totalsize+=$snap->{VolumeSize};
			}
		}
		logtext(0,"    Total used size: $totalsize GB");


	}
		
}


if ( !$dobackup && !$dolifecycle && !$dolistinstances && !$dolistbackups)  {
	
	logtext(0,"Nothing to do ?!?!. Go to help");
	my $help = <<'END';
	Backups/Snapshots Manager in Amazon
	Use: backupmanager.pl  [ --backup [--instanceid=<instance_id>] [--type=<tipo>] ] [--lifecycle] [--listinstances] [--listbackups [--instanceid=<instance_id>] ]

		--backup        : Run backups/snapshots of all instances or one instance if paramater "--instanceid" presents
		--instanceid    : Specify instance (<instance_id>, for example i-12345678) in actions "backup" y "listbackup"
		--type          : Specify tag of type of backup. By default "AUTO". If you specify instanceid parameter by default "ONDEMAND"
		--lifecycle     : Run removing of old backups/snapshots 
		--listinstances : Show list of running instances
		--listbackups   : Show list of availables backups/snapshots for one instance

END
	print "\n$help\n";
	exit 1;

}

exit;



sub logtext {

	my $level=$_[0];
	my $text=$_[1];

	if ($level <= $debuglevel) {
		print strftime("%F %X",localtime)." - ".$text."\n";
	}
}


sub getinstances {

	my $ifilter="";
	if ( defined($_[0]) ) {
		$ifilter="--instance-ids ".$_[0];
	} 
	my $instances_text=`aws ec2 describe-instances $ifilter --filters Name=instance-state-name,Values=running 2>&1 </dev/null`;
	return $instances_text;
}


sub createtag {
	my $resourceid=$_[0];
	my $key=$_[1];
	my $value=$_[2];

	my $cmd="aws ec2 create-tags --resources $resourceid --tags Key='$key',Value='$value' ";
	`$cmd`;
}

