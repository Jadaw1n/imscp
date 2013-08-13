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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# @category    i-MSCP
# @copyright   2010-2013 by i-MSCP | http://i-mscp.net
# @author      Daniel Andreca <sci2tech@gmail.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package Modules::Certificates;

use strict;
use warnings;

use iMSCP::Debug;
use File::Temp;
use iMSCP::File;
use iMSCP::Dir;
use iMSCP::OpenSSL;
use parent 'Modules::Abstract';

sub _init
{
	my $self = shift;

	$self->{'type'} = 'Certificates';
	$self->{'certsDir'} = "$main::imscpConfig{'GUI_ROOT_DIR'}/data/certs";

	my $rs = iMSCP::Dir->new('dirname' => $self->{'certsDir'})->make(
		{ 'mode' => 0750, 'owner' => $main::imscpConfig{'ROOT_USER'}, 'group' => $main::imscpConfig{'ROOT_GROUP'} }
	);
	return $rs if $rs;

	$self;
}

sub loadData
{
	my $self = shift;

	my $sql = "SELECT * FROM `ssl_certs` WHERE `cert_id` = ?";

	my $certData = iMSCP::Database->factory()->doQuery('cert_id', $sql, $self->{'cert_id'});
	unless(ref $certData eq 'HASH') {
		error($certData);
		return 1;
	}

	unless(exists $certData->{$self->{'cert_id'}}) {
		error("No record in table cert_ssl has id = $self->{'cert_id'}");
		return 1;
	}

	$self->{$_} = $certData->{$self->{'cert_id'}}->{$_} for keys %{$certData->{$self->{'cert_id'}}};

	if($self->{'type'} eq 'dmn') {
		$sql = 'SELECT `domain_name` AS `name`, `domain_id` AS `id` FROM `domain` WHERE `domain_id` = ?';
	} elsif($self->{'type'} eq 'als') {
		$sql = 'SELECT `alias_name` AS `name`, `alias_id` AS `id` FROM `domain_aliasses` WHERE `alias_id` = ?';
	} elsif($self->{'type'} eq 'sub') {
		$sql = "
			SELECT
				CONCAT(`subdomain_name`, '.', `domain_name`) AS `name`, `subdomain_id` AS `id`
			FROM
				`subdomain`
			LEFT JOIN
				`domain` USING(`domain_id`)
			WHERE
				`subdomain_id` = ?
		";
	} else {
		$sql = "
			SELECT
				CONCAT(`subdomain_alias_name`, '.', `alias_name`) AS `name`, `subdomain_alias_id` AS `id`
			FROM
				`subdomain_alias`
			LEFT JOIN
				`domain_aliasses` USING(`alias_id`)
			WHERE
				`subdomain_alias_id` = ?
		";
	}

	my $rdata = iMSCP::Database->factory()->doQuery('id', $sql, $self->{'id'});
	unless(ref $rdata eq 'HASH') {
		error($rdata);
		return 1;
	}

	unless(exists $rdata->{$self->{'id'}}) {
		error("No record in table $self->{'type'} has id = $self->{'id'}");
		return 1;
	}

	unless($rdata->{$self->{'id'}}->{'name'}) {
		require Data::Dumper;
		Data::Dumper->import();
		local $Data::Dumper::Terse = 1;
		error('Orphan entry: ' . Dumper($certData->{$self->{'cert_id'}}));

		my @sql = (
			"UPDATE `ssl_certs` SET `status` = ? WHERE `cert_id` = ?",
			'Orphan entry: ' . Dumper($rdata->{$self->{'cert_id'}}), $self->{'cert_id'}
		);

		my $rdata = iMSCP::Database->factory()->doQuery('update', @sql);
		return 1;
	}

	$self->{'name'} = $rdata->{$self->{'id'}}->{'name'};

	0;
}

sub process
{
	my $self = shift;

	$self->{'cert_id'} = shift;

	my $rs = $self->loadData();
	return $rs if $rs;

	my @sql;

	if($self->{'status'} =~ /^toadd|tochange/) {
		$rs = $self->add();
		@sql = (
			"UPDATE `ssl_certs` SET `status` = ? WHERE `cert_id` = ?",
			($rs ? scalar getMessageByType('error') : 'ok'), $self->{'cert_id'}
		);
	} elsif($self->{'status'} eq 'todelete') {
		$rs = $self->delete();
		if($rs) {
			@sql = (
				"UPDATE `ssl_certs` SET `status` = ? WHERE `cert_id` = ?",
				scalar getMessageByType('error'), $self->{'cert_id'}
			);
		} else {
			@sql = ("DELETE FROM `ssl_certs` WHERE `cert_id` = ?", $self->{'cert_id'});
		}
	}

	my $rdata = iMSCP::Database->factory()->doQuery('dummy', @sql);
	unless(ref $rdata eq 'HASH') {
		error($rdata);
		return 1;
	}

	$rs;
}

sub add
{
	my $self = shift;

	my $openSSL = iMSCP::OpenSSL->getInstance();

	# Create temporary file for certificate
	my $certFH = File::Temp->new();

	# Write certificate from database into temporary file
	my $file = iMSCP::File->new('filename' => $certFH->filename);
	$file->set($self->{'cert'});
	my $rs = $file->save();
	return $rs if $rs;

	# Set certificate file path on openssl module
	$openSSL->{'cert_path'} = $certFH->filename;

	# Create temporary file for private key
	my $keyFH = File::Temp->new();

	# Write private key from database into temporary file
	$file = iMSCP::File->new('filename' => $keyFH->filename);
	$file->set($self->{'key'});
	$rs = $file->save();
	return $rs if $rs;

	# Set key file path on openssl module
	$openSSL->{'key_path'} = $keyFH->filename;

	my $caFH;

	if($self->{'ca_cert'}) {
		# Create temporary file for certificate authority
		$caFH = File::Temp->new();

		# Write certificate authority from database into temporary file
		$file = iMSCP::File->new('filename' => $caFH->filename);
		$file->set($self->{'ca_cert'});
		$rs = $file->save();
		return $rs if $rs;

		# Set certificate authority file path on openssl module
		$openSSL->{'intermediate_cert_path'} = $caFH->filename;
	} else {
		$openSSL->{'intermediate_cert_path'} = '';
	}

	# Set openssl binary path on openssl module
	$openSSL->{'openssl_path'} = $main::imscpConfig{'CMD_OPENSSL'};

	# Set privata key password
	$openSSL->{'key_pass'} = $self->{'password'};

	# Check certificate, private key and certificate authority
	$rs = $openSSL->ssl_check_all();
	return $rs if $rs;

	# Set directory path to which certificate should be exported
	$openSSL->{'new_cert_path'} = $self->{'certsDir'};

	$openSSL->{'new_cert_name'} = $self->{'name'};
	$openSSL->{'cert_selfsigned'} = 0;

	$openSSL->ssl_export_all();

	0;
}

sub delete
{
	my $self = shift;

	my $certFile = "$self->{'certsDir'}/$self->{'name'}.pem";
	my $rs = 0;

	$rs = iMSCP::File->new('filename' => $certFile)->delFile() if -f $certFile;
	return $rs if $rs;

	0;
}

1;
