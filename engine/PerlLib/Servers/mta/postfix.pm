#!/usr/bin/perl

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2013 by internet Multi Server Control Panel
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# @category    i-MSCP
# @copyright   2010-2013 by i-MSCP | http://i-mscp.net
# @author      Daniel Andreca <sci2tech@gmail.com>
# @author      Laurent Declercq <l.declercq@nuxwin.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package Servers::mta::postfix;

use strict;
use warnings;

use iMSCP::Debug;
use iMSCP::HooksManager;
use iMSCP::Config;
use iMSCP::Execute;
use iMSCP::File;
use iMSCP::Dir;
use File::Basename;
use parent 'Common::SingletonClass';

sub _init
{
	my $self = shift;

	$self->{'hooksManager'} = iMSCP::HooksManager->getInstance();

	$self->{'hooksManager'}->trigger(
		'beforeMtaInit', $self, 'postfix'
	) and fatal('postfix - beforeMtaInit hook has failed');

	$self->{'cfgDir'} = "$main::imscpConfig{'CONF_DIR'}/postfix";
	$self->{'bkpDir'} = "$self->{'cfgDir'}/backup";
	$self->{'wrkDir'} = "$self->{'cfgDir'}/working";

	$self->{'commentChar'} = '#';

	tie %{$self->{'config'}}, 'iMSCP::Config', 'fileName' => "$self->{'cfgDir'}/postfix.data";

	$self->{'hooksManager'}->trigger(
		'afterMtaInit', $self, 'postfix'
	) and fatal('postfix - afterMtaInit hook has failed');

	$self;
}

sub registerSetupHooks
{
	my $self = shift;
	my $hooksManager = shift;

	my $rs = $hooksManager->trigger('beforeMtaRegisterSetupHooks', $hooksManager, 'postfix');
	return $rs if $rs;

	$hooksManager->trigger('afterMtaRegisterSetupHooks', $hooksManager, 'postfix');
}

sub preinstall
{
	my $self = shift;

	require Servers::mta::postfix::installer;
	Servers::mta::postfix::installer->getInstance()->preinstall();
}

sub install
{
	my $self = shift;

	require Servers::mta::postfix::installer;
	Servers::mta::postfix::installer->getInstance()->install();
}

sub uninstall
{
	my $self = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaUninstall', 'postfix');
	return $rs if $rs;

	require Servers::mta::postfix::uninstaller;

	$rs = Servers::mta::postfix::uninstaller->getInstance()->uninstall();
	return $rs if $rs;

	$rs = $self->restart();
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaUninstall', 'postfix');
}

sub postinstall
{
	my $self = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaPostinstall', 'postfix');
	return $rs if $rs;

	$self->{'restart'} = 'yes';

	$self->{'hooksManager'}->trigger('afterMtaPostinstall', 'postfix');
}

sub setEnginePermissions
{
	my $self= shift;

	require Servers::mta::postfix::installer;
	Servers::mta::postfix::installer->getInstance()->setEnginePermissions();
}

sub restart
{
	my $self = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaRestart');
	return $rs if $rs;

	my ($stdout, $stderr);
	$rs = execute("$self->{'config'}->{'CMD_MTA'} restart", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaRestart');
}

sub postmap
{
	my $self = shift;
	my $filename = shift;
	my $filetype = shift || 'hash';

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaPostmap', \$filename, \$filetype);
	return $rs if $rs;

	my ($stdout, $stderr);
	$rs = execute("$self->{'config'}->{'CMD_POSTMAP'} $filetype:$filename", \$stdout, \$stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaPostmap', $filename, $filetype);
}

sub addDmn
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddDmn', $data);
	return $rs if $rs;

	if($data->{'EXTERNAL_MAIL'} eq 'on') { # Mail for both domain and subdomains is managed by external server
		# Remove entry from the Postfix virtual_mailbox_domains map
		$rs = $self->disableDmn($data);
		return $rs if $rs;

		if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
			# Remove any previous entry of this domain from the Postfix relay_domains map
			$rs = $self->deleteFromRelayHash($data);
			return $rs if $rs;

			# Add the domain entry to the Postfix relay_domain map
			$rs = $self->addToRelayHash($data);
			return $rs if $rs;
		}
	} elsif($data->{'EXTERNAL_MAIL'} eq 'wildcard') { # Only mail for in-existent subdomains is managed by external server
		# Add the domain or subdomain entry to the Postfix virtual_mailbox_domains map
		$rs = $self->addToDomainHash($data);
		return $rs if $rs;

		if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
			# Remove any previous entry of this domain from the Postfix relay_domains map
			$rs = $self->deleteFromRelayHash($data);
			return $rs if $rs;

			# Add the wildcard entry for in-existent subdomains to the Postfix relay_domain map
			$rs = $self->addToRelayHash($data);
			return $rs if $rs;
		}
	} else { # Mail for both domain and subdomains is managed by iMSCP mail host
		# Add domain or subdomain entry to the Postfix virtual_mailbox_domains map
		$rs = $self->addToDomainHash($data);
		return $rs if $rs;

		if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
			# Remove any previous entry of this domain from the Postfix relay_domains map
			$rs = $self->deleteFromRelayHash($data);
			return $rs if $rs;
		}
	}

	$self->{'hooksManager'}->trigger('afterMtaAddDmn', $data);
}

sub addToRelayHash
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddToRelayHash', $data);
	return $rs if $rs;

	my $entry = "$data->{'DOMAIN_NAME'}\t\t\tOK\n";

	if($data->{'EXTERNAL_MAIL'} eq 'wildcard') { # For wildcard MX, we add entry such as ".domain.tld"
		$entry = '.' . $entry;
	}

	$rs = iMSCP::File->new(
		'filename' => $self->{'config'}->{'MTA_RELAY_HASH'}
	)->copyFile("$self->{'bkpDir'}/relay_domains." . time);
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => "$self->{'wrkDir'}/relay_domains");
	my $content = $file->get();

	if(! defined $content){
		error("Unable to read $self->{'wrkDir'}/relay_domains");
		return 1;
	}

	$content .= $entry unless $content =~ /^$entry/mg;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($self->{'config'}->{'MTA_RELAY_HASH'});
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_RELAY_HASH'}} = $data->{'DOMAIN_NAME'};

	$self->{'hooksManager'}->trigger('afterMtaAddToRelayHash', $data);
}

sub deleteFromRelayHash
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelFromRelayHash', $data);
	return $rs if $rs;

	my $entry = "\.?$data->{'DOMAIN_NAME'}\t\t\tOK\n"; # Match both "domain.tld" and ".domain.tld" entries

	$rs = iMSCP::File->new(
		'filename' => $self->{'config'}->{'MTA_RELAY_HASH'}
	)->copyFile("$self->{'bkpDir'}/relay_domains." . time);
	return $rs if $rs;

	my $file= iMSCP::File->new('filename' => "$self->{'wrkDir'}/relay_domains");
	my $content = $file->get();

	if(! defined $content){
		error("Unable to read $self->{'wrkDir'}/relay_domains");
		return 1;
	}

	$content =~ s/^$entry//mg;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($self->{'config'}->{'MTA_RELAY_HASH'});
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_RELAY_HASH'}} = $data->{'DOMAIN_NAME'};

	$self->{'hooksManager'}->trigger('afterMtaDelFromRelayHash', $data);
}

sub addToDomainHash
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddToDomainHash', $data);
	return $rs if $rs;

	my $entry = "$data->{'DOMAIN_NAME'}\t\t\t$data->{'TYPE'}\n";

	$rs = iMSCP::File->new(
		'filename' => $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}
	)->copyFile( "$self->{'bkpDir'}/domains." . time );
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => "$self->{'wrkDir'}/domains");
	my $content = $file->get();

	if(! defined $content){
		error("Unable to read $self->{'wrkDir'}/domains");
		return 1;
	}

	$content .= $entry unless $content =~ /^$entry/mg;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'});
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}} = $data->{'DOMAIN_NAME'};

	$rs = iMSCP::Dir->new(
		'dirname' => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}"
	)->make(
		{
			'user' => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
			'group' => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
			'mode' => 0750
		}
	);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaAddToDomainHash', $data);
}

sub deleteDmn
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelDmn', $data);
	return $rs if $rs;

	$rs = $self->disableDmn($data);
	return $rs if $rs;

	$rs = iMSCP::Dir->new(
		'dirname' => "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}"
	)->remove();
	return $rs if $rs;

	$rs = $self->{'hooksManager'}->trigger('afterMtaDelDmn', $data);
}

sub disableDmn
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableDmn', $data);
	return $rs if $rs;

	my $entry = "$data->{'DOMAIN_NAME'}\t\t\t$data->{'TYPE'}\n";

	$rs = iMSCP::File->new(
		'filename' => $self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}
	)->copyFile("$self->{'bkpDir'}/domains." . time);
	return $rs if $rs;

	my $file = iMSCP::File->new('filename' => "$self->{'wrkDir'}/domains");
	my $content = $file->get();

	if(! defined $content){
		error("Unable to read $self->{'wrkDir'}/domains");
		return 1;
	}

	$content =~ s/^$entry//mg;

	$rs = $file->set($content);
	return $rs if $rs;

	$rs = $file->save();
	return $rs if $rs;

	$rs = $file->mode(0644);
	return $rs if $rs;

	$rs = $file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $file->copyFile($self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'});
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_DMN_HASH'}} = $data->{'DOMAIN_NAME'};

	if($data->{'DOMAIN_TYPE'} eq 'Dmn') {
		$rs = $self->deleteFromRelayHash($data);
		return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaDisableDmn', $data);
}

sub addSub
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddSub', $data);
	return $rs if $rs;

	$rs = $self->addDmn($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaAddSub', $data);
}

sub deleteSub
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelSub', $data);
	return $rs if $rs;

	$rs = $self->deleteDmn($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDelSub', $data);
}

sub disableSub
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableSub', $data);
	return $rs if $rs;

	$rs = $self->disableDmn($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDisableSub', $data);
}

sub addMail
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddMail', $data);
	return $rs if $rs;

	for(
		$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'},
		$self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
		$self->{'config'}->{'MTA_TRANSPORT_HASH'}
	) {
		if(-f $_) {
			my $file = iMSCP::File->new('filename' => $_);
			my ($filename, $directories, $suffix) = fileparse($_);

			$rs = iMSCP::File->new(
				'filename' => $_
			)->copyFile(
				"$self->{'bkpDir'}/$filename$suffix." . time
			);
			return $rs if $rs;
		}
	}

	$rs = $self->addSaslData($data) if $data->{'MAIL_TYPE'} =~ m/_mail/;
	return $rs if $rs;

	$rs = $self->deleteSaslData($data) if $data->{'MAIL_TYPE'} !~ m/_mail/;
	return $rs if $rs;

	$rs = $self->addMailBox($data) if $data->{'MAIL_TYPE'} =~ m/_mail/;
	return $rs if $rs;

	$rs = $self->deleteMailBox($data) if $data->{'MAIL_TYPE'} !~ m/_mail/;
	return $rs if $rs;

	$rs = $self->addAutoRspnd($data) if $data->{'MAIL_HAS_AUTO_RSPND'}  eq 'yes';
	return $rs if $rs;

	$rs = $self->deleteAutoRspnd($data) if $data->{'MAIL_HAS_AUTO_RSPND'} eq 'no';
	return $rs if $rs;

	$rs = $self->addMailForward($data) if $data->{'MAIL_TYPE'} =~ m/_forward/;
	return $rs if $rs;

	$rs = $self->deleteMailForward($data) if $data->{'MAIL_TYPE'} !~ m/_forward/;
	return $rs if $rs;

	$rs = $self->addCatchAll($data) if $data->{'MAIL_HAS_CATCH_ALL'} eq 'yes';
	return $rs if $rs;

	$rs = $self->deleteCatchAll($data) if $data->{'MAIL_HAS_CATCH_ALL'} eq 'no';
	return $rs if $rs;


	$self->{'hooksManager'}->trigger('afterMtaAddMail', $data);
}

sub deleteMail
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelMail', $data);
	return $rs if $rs;

	for(
		$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'},
		$self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
		$self->{'config'}->{'MTA_TRANSPORT_HASH'}
	) {
		if(-f $_) {
			my $file = iMSCP::File->new('filename' => $_);
			my ($filename, $directories, $suffix) = fileparse($_);

			$rs = iMSCP::File->new(
				'filename' => $_
			)->copyFile(
				"$self->{'bkpDir'}/$filename$suffix." . time
			);
			return $rs if $rs;
		}
	}

	$rs = $self->deleteSaslData($data);
	return $rs if $rs;

	$rs = $self->deleteMailBox($data);
	return $rs if $rs;

	$rs = $self->deleteMailForward($data);
	return $rs if $rs;

	$rs = $self->deleteAutoRspnd($data);
	return $rs if $rs;

	$rs = $self->deleteCatchAll($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDelMail', $data);
}

sub disableMail
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableMail', $data);
	return $rs if $rs;

	for(
		$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'},
		$self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'},
		$self->{'config'}->{'MTA_TRANSPORT_HASH'}
	){
		if(-f $_) {
			my $file = iMSCP::File->new('filename' => $_);
			my ($filename, $directories, $suffix) = fileparse($_);

			$rs = iMSCP::File->new(
				'filename' => $_
			)->copyFile(
				"$self->{'bkpDir'}/$filename$suffix." . time
			);
			return $rs if $rs;
		}
	}

	$rs = $self->deleteSaslData($data);
	return $rs if $rs;

	$rs = $self->disableMailBox($data);
	return $rs if $rs;

	$rs = $self->deleteMailForward($data);
	return $rs if $rs;

	$rs = $self->deleteAutoRspnd($data);
	return $rs if $rs;

	$rs = $self->deleteCatchAll($data);
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDisableMail', $data);
}

sub deleteSaslData
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelSaslData', $data);
	return $rs if $rs;

	my ($stdout, $stderr);

	my $mailBox = $data->{'MAIL_ADDR'};
	$mailBox =~ s/\./\\\./g;

	my $sasldb = iMSCP::File->new('filename' => $self->{'config'}->{'ETC_SASLDB_FILE'});

	$rs = $sasldb->save() unless -f $self->{'config'}->{'ETC_SASLDB_FILE'};
	return $rs if $rs;

	$rs = $sasldb->mode(0660);
	return $rs if $rs;

	$rs = $sasldb->owner($self->{'config'}->{'SASLDB_USER'}, $self->{'config'}->{'SASLDB_GROUP'});
	return $rs if $rs;

	$rs = execute(
		"$self->{'config'}->{'CMD_SASLDB_LISTUSERS2'} -f $self->{'config'}->{'ETC_SASLDB_FILE'}", \$stdout, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	if($stdout =~ m/^$mailBox:/mgi) {
		$rs = execute(
			"$self->{'config'}->{'CMD_SASLDB_PASSWD2'} -d -f $self->{'config'}->{'ETC_SASLDB_FILE'} " .
			"-u $data->{'DOMAIN_NAME'} $data->{'MAIL_ACC'}",
			\$stdout,
			\$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;

		if($self->{'config'}->{'ETC_SASLDB_FILE'} ne $self->{'config'}->{'MTA_SASLDB_FILE'}) {
			$rs = execute(
				"$main::imscpConfig{'CMD_CP'} -fp $self->{'config'}->{'ETC_SASLDB_FILE'} " .
				"$self->{'config'}->{'MTA_SASLDB_FILE'}",
				\$stdout,
				\$stderr
			);
			debug($stdout) if $stdout;
			error($stderr) if $stderr && $rs;
			return $rs if $rs;
		}
	}

	$self->{'hooksManager'}->trigger('afterMtaDelSaslData', $data);
}

sub addSaslData
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddSaslData', $data);
	return $rs if $rs;

	my ($stdout, $stderr);

	my $mailBox = $data->{'MAIL_ADDR'};
	$mailBox =~ s/\./\\\./g;

	my $sasldb = iMSCP::File->new('filename' => $self->{'config'}->{'ETC_SASLDB_FILE'});

	$rs = $sasldb->save() unless -f $self->{'config'}->{'ETC_SASLDB_FILE'};
	return $rs if $rs;

	$rs = $sasldb->mode(0660);
	return $rs if $rs;

	$rs = $sasldb->owner($self->{'config'}->{'SASLDB_USER'}, $self->{'config'}->{'SASLDB_GROUP'});
	return $rs if $rs;

	$rs = execute(
		"$self->{'config'}->{'CMD_SASLDB_LISTUSERS2'} -f $self->{'config'}->{'ETC_SASLDB_FILE'}", \$stdout, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	if($stdout =~ m/^$mailBox:/mgi) {
		$rs |= execute(
			"$self->{'config'}->{'CMD_SASLDB_PASSWD2'} -d -f $self->{'config'}->{'ETC_SASLDB_FILE'} " .
			"-u $data->{'DOMAIN_NAME'} $data->{'MAIL_ACC'}",
			\$stdout,
			\$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	my $password = escapeShell($data->{'MAIL_PASS'});

	$rs = execute(
		"$main::imscpConfig{'CMD_ECHO'} $password | $self->{'config'}->{'CMD_SASLDB_PASSWD2'} -p -c " .
		"-f $self->{'config'}->{'ETC_SASLDB_FILE'} -u $data->{'DOMAIN_NAME'} $data->{'MAIL_ACC'}",
		\$stdout,
		\$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	return $rs if $rs;

	if($self->{'config'}->{'ETC_SASLDB_FILE'} ne $self->{'config'}->{'MTA_SASLDB_FILE'}) {
		$rs = execute(
			"$main::imscpConfig{'CMD_CP'} -fp $self->{'config'}->{'ETC_SASLDB_FILE'} " .
			"$self->{'config'}->{'MTA_SASLDB_FILE'}",
			\$stdout,
			\$stderr
		);
		debug($stdout) if $stdout;
		error($stderr) if $stderr && $rs;
		return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaAddSaslData', $data);
}

sub deleteAutoRspnd
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelAutoRspnd', $data);
	return $rs if $rs;

	my $mTrsptHshFile = $self->{'config'}->{'MTA_TRANSPORT_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mTrsptHshFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	my $trnsprt = "imscp-arpl.$data->{'DOMAIN_NAME'}";
	$trnsprt =~ s/\./\\\./g;
	$wrkContent =~ s/^$trnsprt\t[^\n]*\n//gmi;

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mTrsptHshFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_TRANSPORT_HASH'}} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDelAutoRspnd', $data);
}

sub addAutoRspnd
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddAutoRspnd', $data);
	return $rs if $rs;

	my $mTrsptHshFile = $self->{'config'}->{'MTA_TRANSPORT_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mTrsptHshFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	my $trnsprt = "imscp-arpl.$data->{'DOMAIN_NAME'}";
	$trnsprt =~ s/\./\\\./g;
	$wrkContent =~ s/^$trnsprt\t[^\n]*\n//gmi;
	$wrkContent .= "imscp-arpl.$data->{'DOMAIN_NAME'}\timscp-arpl:\n";

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mTrsptHshFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_TRANSPORT_HASH'}} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaAddAutoRspnd', $data);
}

sub deleteMailForward
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelMailForward', $data);
	return $rs if $rs;

	my $mFWDHshFile = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mFWDHshFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	my $mailbox = $data->{'MAIL_ADDR'};
	$mailbox =~ s/\./\\\./g;
	$wrkContent =~ s/^$mailbox\t[^\n]*\n//gmi;

	# Handle normal mail accounts entries for which auto-responder is active
	if($data->{'MAIL_STATUS'} ne 'todelete') {
		my @line;

		# If auto-responder is activated, we must add the recipient as address to keep local copy of any forwarded mail
		push(@line, $data->{'MAIL_ADDR'}) if $data->{'MAIL_AUTO_RSPND'} && $data->{'MAIL_TYPE'} =~ m/_mail/;

		# If auto-responder is activated, we need an address such as user@imscp-arpl.domain.tld
		push(@line, "$data->{'MAIL_ACC'}\@imscp-arpl.$data->{'DOMAIN_NAME'}")
			if $data->{'MAIL_AUTO_RSPND'} && $data->{'MAIL_TYPE'} =~ m/_mail/;

		$wrkContent .= "$data->{'MAIL_ADDR'}\t" . join(',', @line) . "\n" if scalar @line;
	}

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mFWDHshFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDelMailForward', $data);
}

sub addMailForward
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddMailForward', $data);
	return $rs if $rs;

	my $mFWDHshFile = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mFWDHshFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	my $mailbox = $data->{'MAIL_ADDR'};
	$mailbox =~ s/\./\\\./g;
	$wrkContent =~ s/^$mailbox\t[^\n]*\n//gmi;

	my @line;

	# For a normal+foward mail account, we must add the recipient as address to keep local copy of any forwarded mail
	push(@line, $data->{'MAIL_ADDR'}) if $data->{'MAIL_TYPE'} =~ m/_mail/;

	# Add address(s) to which mail will be forwarded
	push(@line, $data->{'MAIL_FORWARD'});

	# If the auto-responder is activated, we must add an address such as user@imscp-arpl.domain.tld
	push(@line, "$data->{'MAIL_ACC'}\@imscp-arpl.$data->{'DOMAIN_NAME'}") if $data->{'MAIL_AUTO_RSPND'};

	$wrkContent .= "$data->{'MAIL_ADDR'}\t" . join(',', @line) . "\n" if scalar @line;

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mFWDHshFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaAddMailForward', $data);
}

sub deleteMailBox
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelMailbox', $data);
	return $rs if $rs;

	$rs = $self->disableMailBox($data);
	return $rs if $rs;

	return $rs if ! $data->{'MAIL_ACC'}; # catchall?

	my $mailDir = "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}/$data->{'MAIL_ACC'}";

	$rs = iMSCP::Dir->new('dirname' => $mailDir)->remove();
	return $rs if $rs;

	$self->{'hooksManager'}->trigger('afterMtaDelMailbox', $data);
}

sub disableMailBox
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDisableMailbox', $data);
	return $rs if $rs;

	my $mBoxHashFile = $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mBoxHashFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	my $mailbox = $data->{'MAIL_ADDR'};
	$mailbox =~ s/\./\\\./g;
	$wrkContent =~ s/^$mailbox\t[^\n]*\n//gmi;

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mBoxHashFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDisableMailbox', $data);
}

sub addMailBox
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddMailbox', $data);
	return $rs if $rs;

	my $mBoxHashFile = $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mBoxHashFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	my $mailbox = $data->{'MAIL_ADDR'};
	$mailbox =~ s/\./\\\./g;
	$wrkContent =~ s/^$mailbox\t[^\n]*\n//gmi;
	$wrkContent .= "$data->{'MAIL_ADDR'}\t$data->{'DOMAIN_NAME'}/$data->{'MAIL_ACC'}/\n";

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mBoxHashFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_MAILBOX_HASH'}} = $data->{'MAIL_ADDR'};

	my $mailDir = "$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}/$data->{'DOMAIN_NAME'}/$data->{'MAIL_ACC'}";
	my $mailUidName = $self->{'config'}->{'MTA_MAILBOX_UID_NAME'};
    my $mailGidName = $self->{'config'}->{'MTA_MAILBOX_GID_NAME'};

	# Creating maildir directory or only set its permissions if already exists
	$rs = iMSCP::Dir->new(
		'dirname' => $mailDir
	)->make(
		{
			'user' => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
			'group' => $self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
			'mode' => 0750
		}
	);
	return $rs if $rs;

	# Creating maildir sub folders (cur, new, tmp) or only set there permissions if they already exists
	for('cur', 'new', 'tmp') {
    	$rs = iMSCP::Dir->new(
    		'dirname' => "$mailDir/$_"
    	)->make(
    		{ 'user' => $mailUidName, 'group' => $mailGidName, 'mode' => 0750 }
    	);
    	return $rs if $rs;
	}

	$self->{'hooksManager'}->trigger('afterMtaAddMailbox', $data);
}

sub addCatchAll
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaAddCatchAll', $data);
	return $rs if $rs;

	my $mFWDHshFile = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mFWDHshFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	for(@{$data->{'MAIL_ON_CATCHALL'}}) {
		my $mailbox = $_;
		$mailbox =~ s/\./\\\./g;
		$wrkContent =~ s/^$mailbox\t$mailbox\n//gmi;
		$wrkContent .= "$_\t$_\n";
	}

	if($data->{'MAIL_TYPE'} =~ m/_catchall/) {
		my $catchAll = "\@$data->{'DOMAIN_NAME'}";
		$catchAll =~ s/\./\\\./g;
		$wrkContent =~ s/^$catchAll\t[^\n]*\n//gmi;
		$wrkContent .= "\@$data->{'DOMAIN_NAME'}\t$data->{'MAIL_CATCHALL'}\n";
	}

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mFWDHshFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaAddCatchAll', $data);
}

sub deleteCatchAll
{
	my $self = shift;
	my $data = shift;

	my $rs = $self->{'hooksManager'}->trigger('beforeMtaDelCatchAll', $data);
	return $rs if $rs;

	my $mFWDHshFile = $self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'};
	my ($filename, $directories, $suffix) = fileparse($mFWDHshFile);
	my $wrkFileName = "$self->{'wrkDir'}/$filename$suffix";

	my $wrkFile = iMSCP::File->new('filename' => $wrkFileName);
	my $wrkContent = $wrkFile->get();
	return 1 unless defined $wrkContent;

	for(@{$data->{'MAIL_ON_CATCHALL'}}) {
		my $mailbox = $_;
		$mailbox =~ s/\./\\\./g;
		$wrkContent =~ s/^$mailbox\t$mailbox\n//gmi;
	}

	my $catchAll = "\@$data->{'DOMAIN_NAME'}";
	$catchAll =~ s/\./\\\./g;
	$wrkContent =~ s/^$catchAll\t[^\n]*\n//gmi;

	$rs = $wrkFile->set($wrkContent);
	return $rs if $rs;

	$rs = $wrkFile->save();
	return $rs if $rs;

	$rs = $wrkFile->mode(0644);
	return $rs if $rs;

	$rs = $wrkFile->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	return $rs if $rs;

	$rs = $wrkFile->copyFile($mFWDHshFile);
	return $rs if $rs;

	$self->{'postmap'}->{$self->{'config'}->{'MTA_VIRTUAL_ALIAS_HASH'}} = $data->{'MAIL_ADDR'};

	$self->{'hooksManager'}->trigger('afterMtaDelCatchAll', $data);
}

sub getTraffic
{
	my $self = shift;
	my $who = shift;

	my $dbName = "$self->{'wrkDir'}/log.db";
	my $logFile = "$main::imscpConfig{'TRAFF_LOG_DIR'}/mail.log";
	my $wrkLogFile = "$main::imscpConfig{'LOG_DIR'}/mail.smtp.log";
	my ($rs, $rv, $stdout, $stderr);

	$self->{'hooksManager'}->trigger('beforeMtaGetTraffic') and return 0;

	# Only if files was not aleady parsed this session
	unless($self->{'logDb'}) {
		# Use a small conf file to memorize last line readed and his content
		tie %{$self->{'logDb'}}, 'iMSCP::Config', 'fileName' => $dbName, 'noerrors' => 1;

		# First use? we zero line and content
		$self->{'logDb'}->{'line'} = 0 unless $self->{'logDb'}->{'line'};
		$self->{'logDb'}->{'content'} = '' unless $self->{'logDb'}->{'content'};
		my $lastLineNo = $self->{'logDb'}->{'line'};
		my $lastLine = $self->{'logDb'}->{'content'};

		# Copy log file
		$rs = iMSCP::File->new('filename' => $logFile)->copyFile($wrkLogFile) if -f $logFile;
		return 0 if $rs; # return 0 traffic if we fail

		# Link log file to array
		require Tie::File;
		tie my @content, 'Tie::File', $wrkLogFile or return 0;

		# save last line
		$self->{'logDb'}->{'line'} = $#content;
		$self->{'logDb'}->{'content'} = $content[$#content];

		# Test for logratation
		if($content[$lastLineNo] && $content[$lastLineNo] eq $lastLine) {
			# No logratation ocure. We zero already readed files
			(tied @content)->defer;
			@content = @content[$lastLineNo + 1 .. $#content];
			(tied @content)->flush;
		}

		$rs = execute(
			"$main::imscpConfig{'CMD_GREP'} 'postfix' $wrkLogFile | $self->{'config'}->{'CMD_PFLOGSUM'} standard",
			\$stdout,
			\$stderr
		);
		error($stderr) if $stderr && $rs;
		return 0 if $rs;

		while($stdout =~ m/^[^\s]+\s[^\s]+\s[^\s\@]+\@([^\s]+)\s[^\s\@]+\@([^\s]+)\s([^\s]+)\s([^\s]+)\s[^\s]+\s[^\s]+\s[^\s]+\s(.*)$/mg){
						 #  date    time    mailfrom @ domain   mailto   @ domain    relay_s   relay_r   SMTP  extinfo  code     size
						 #                                1                  2         3         4                                 5
			if($5 ne '?' && $4 !~ /virtual/ && !($3 =~ /localhost|127.0.0.1/ && $4 =~ /localhost|127.0.0.1/)){
				$self->{'traff'}->{$1} += $5;
				$self->{'traff'}->{$2} += $5;
			}
		}
	}

	$self->{'hooksManager'}->trigger('afterMtaGetTraffic') and return 0;

	$self->{'traff'}->{$who} ? $self->{'traff'}->{$who} : 0;
}

END
{
	my $exitCode = $?;
	my $self = Servers::mta::postfix->getInstance();
	my $wrkLogFile = "$main::imscpConfig{'LOG_DIR'}/mail.smtp.log";
	my $rs = 0;

	# In any case we postmap if needed
	for(keys %{$self->{'postmap'}}) {
		$rs |= $self->postmap($_);
	}

	if($self->{'restart'} && $self->{'restart'} eq 'yes') {
		$rs |= $self->restart();
	}

	$rs |= iMSCP::File->new('filename' => $wrkLogFile)->delFile() if -f $wrkLogFile;

	$? = $exitCode || $rs;
}

1;
