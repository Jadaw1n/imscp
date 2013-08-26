#!/usr/bin/perl

=head1 NAME

 Modules::Plugin - i-MSCP Plugin module

=cut

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
# @author      Laurent Declercq <l.declercq@nuxwin.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package Modules::Plugin;

use strict;
use warnings;

use iMSCP::Debug;
use iMSCP::Database;
use iMSCP::HooksManager;
use iMSCP::File;

use parent 'Common::SimpleClass';

my %toStatus = (
	'toinstall' => 'enabled',
	'toenable' => 'enabled',
	'todisable' => 'disabled',
	'touninstall' => 'todelete',
	'enabled' => 'enabled'
);

=head1 DESCRIPTION

 This module is responsible to run actions on the plugins according their current status. To each status correspond a
specific action:

 - toinstall: The 'toinstall' status correspond to the 'install' action. Next status should be 'enabled'.
 	The 'install' action is run on plugin first installation

 - tochange: The 'tochange' status correspond to the 'change' action. Next status should be set to previous status.
 	The 'change' action is run on every i-MSCP update (only if the plugin is enabled)

 - toupdate status: The 'toupdate' status correspond to the 'update' action. Next status should be set to previous status.
 	The 'update' action is run when a plugin is updated (new version or configuration update)

 - touninstall status: The 'touninstall' status correspond to the 'uninstall' action. Next status should be 'todelete'.
	The 'uninstall' action is run when the plugin is uninstalled

 - todisable status: The 'todisable' status correspond to the 'disable' action. Next status should be 'disabled'.
	The 'disable' action is run when a plugin is deactivated

 - toenable status: The 'toenable' status correspond to the 'enable' action. Next sttus should be 'enabled'.
	The 'enable' action is triggered when the plugin is activated

 - enabled status: The 'enabled' status correspond to the 'run' action. Next status should be 'enabled'.
	The 'run' action is run when the plugin is activated, each time a backend request is made

 - other status: No action

 The module will attempt to run these actions on the plugins only if they implement them. It's important to understand
that all status described above belong to the plugins themselves, and not to their own items. In case where a plugin
handle its own items it's its responsability to handle their status if any.

 Note on 'install' action:

 When the 'install' action is run, the backend part of the plugin is installed from the plugin package into the
imscp/engine/Plugins directory, which is the plugins backend repository. The plugin file must be located in a specific
subdirectory of plugin package:

 <PluginName>/backend/<PluginName>.pm

 Plugin packages are located under the imscp/gui/plugins directory.

 Note on 'uninstall' action:

 When the 'uninstall' action is run, the backend part of the plugin is removed from the backend plugins repository.



=head1 PUBLIC METHODS

=over 4

=item loadData()

 Load plugin data from database

 Return 0 on success, 1 on failure

=cut

sub loadData
{
	my $self = shift;
	my $pluginId = shift;

	my $rdata = iMSCP::Database->factory()->doQuery(
		'plugin_id',
		'
			SELECT
				`plugin_id`, `plugin_name`, `plugin_status`, `plugin_previous_status`
			FROM
				`plugin`
			WHERE
				`plugin_id` = ?
		',
		$pluginId
	);
	unless(ref $rdata eq 'HASH') {
		error($rdata);
		return 1;
	}

	unless(exists $rdata->{$pluginId}) {
		error("No plugin has ID: $pluginId");
		return 1
	}

	@{$self}{keys %{$rdata->{$pluginId}}} = values %{$rdata->{$pluginId}};

	$toStatus{'toupdate'} = $self->{'plugin_previous_status'};
	$toStatus{'tochange'} = $self->{'plugin_previous_status'};

	0;
}

=item process($pluginId)

 Process plugin action according it status

 Param int Plugin unique identifier
 Return int 0 on success, other on failure

=cut

sub process($$)
{
	my $self = shift;
	my $pluginId = shift;

	my $rs = $self->loadData($pluginId);
	return $rs if $rs;

	my $status = $self->{'plugin_status'};

	if($status eq 'enabled') {
		$rs = $self->_executePlugin('run');
	} elsif($status eq 'toinstall') {
		$rs = $self->_executePlugin('install');
	} elsif($status eq 'tochange') {
		$rs = $self->_executePlugin('change');
	} elsif($status eq 'toupdate') {
		$rs = $self->_executePlugin('update');
	} elsif($status eq 'touninstall') {
		$rs = $self->_executePlugin('uninstall');
	} elsif($status  eq 'toenable') {
		$rs = $self->_executePlugin('enable');
	} elsif($status eq 'todisable') {
		$rs = $self->_executePlugin('disable');
	} else {
		error("Plugin $self->{'plugin_name'} has an unknown status: $status");
		return 1;
	}

	my $column = ($rs) ? 'plugin_error' : 'plugin_status';

	my @sql = (
		"UPDATE `plugin` SET `$column` = ? WHERE `plugin_id` = ?",
		($rs ? (scalar getMessageByType('error') || 'unknown error') : $toStatus{$status}), $pluginId
	);

	my $rdata = iMSCP::Database->factory()->doQuery('dummy', @sql);
	unless(ref $rdata eq 'HASH') {
		error($rdata);
		return 1;
	}

	$rs;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _executePlugin($action)

 Execute the given plugin action

 Param string Plugin action to call
 Return int 0 on success, other on failure

=cut

sub _executePlugin($$)
{
	my $self = shift;
	my $action = shift;

	my $pluginFile = "$main::imscpConfig{'ENGINE_ROOT_DIR'}/Plugins/$self->{'plugin_name'}.pm";
	my $rs = 0;

	# On both install and update actions, we copy the backend part of the plugin from the GUI plugins directory to
	# the backend plugins directory
	if($action ~~ ['install', 'update']) {
		my $guiPluginDir = "$main::imscpConfig{'GUI_ROOT_DIR'}/plugins";

		if(-f "$guiPluginDir/$self->{'plugin_name'}/backend/$self->{'plugin_name'}.pm") {
			my $file = iMSCP::File->new(
				'filename' => "$guiPluginDir/$self->{'plugin_name'}/backend/$self->{'plugin_name'}.pm"
			);

			$rs = $file->copyFile($pluginFile, { 'preserve' => 'no' });
			return $rs if $rs;
		} else {
			error("Unable to install backend plugin: File $pluginFile not found");
			return 1;
		}
	}

	# We trap any compile time error(s)
	eval { require $pluginFile; };

	if($@) { # We got an error due to compile time error(s) (including missing file error)
		error($@);
		return 1;
	} else {
		my $pluginClass = "Plugin::$self->{'plugin_name'}";
		my $pluginInstance;

		eval {
			# Any backend plugin is a singleton, which receive an iMSCP::HooksManager instance
			$pluginInstance = $pluginClass->getInstance('hooksManager' => iMSCP::HooksManager->getInstance());
		};

		if($@) {
			error("Plugin $self->{'plugin_name'} has an invalid package name. Should be: $pluginClass");
			return 1;
		}

		# We execute the action on the plugin only if it implements it
		if($pluginInstance->can($action)) {
			$rs = $pluginInstance->$action();

			# Return value from run() action is ignored by default because it's the responsability of the plugin to set
			# error status for its items. In case the plugin doesn't manage any item, it can force return value by
			# defining the FORCE_RETVAL attribute and set it to 'yes'
			if(
				$action ne 'run' || defined $pluginInstance->{'FORCE_RETVAL'} &&
				$pluginInstance->{'FORCE_RETVAL'} eq 'yes'
			) {
				return $rs if $rs;
			} else {
				$rs = 0;
			}
		}

		# On both disable and uninstall actions, we remove the backend part of the plugin from the backend plugins
		# directory
		if($action eq 'uninstall') {
			my $file = iMSCP::File->new('filename' => $pluginFile);
			$rs = $file->delFile();
		}
	}

	$rs;
}

=back

=head1 AUTHOR

Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
