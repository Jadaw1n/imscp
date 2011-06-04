<?php
/**
 * i-MSCP a internet Multi Server Control Panel
 *
 * @copyright 	2001-2006 by moleSoftware GmbH
 * @copyright 	2006-2010 by ispCP | http://isp-control.net
 * @copyright 	2010 by i-MSCP | http://i-mscp.net
 * @version 	SVN: $Id$
 * @link 		http://i-mscp.net
 * @author 		ispCP Team
 * @author 		i-MSCP Team
 *
 * @license
 * The contents of this file are subject to the Mozilla Public License
 * Version 1.1 (the "License"); you may not use this file except in
 * compliance with the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * The Original Code is "VHCS - Virtual Hosting Control System".
 *
 * The Initial Developer of the Original Code is moleSoftware GmbH.
 * Portions created by Initial Developer are Copyright (C) 2001-2006
 * by moleSoftware GmbH. All Rights Reserved.
 * Portions created by the ispCP Team are Copyright (C) 2006-2010 by
 * isp Control Panel. All Rights Reserved.
 * Portions created by the i-MSCP Team are Copyright (C) 2010 by
 * i-MSCP a internet Multi Server Control Panel. All Rights Reserved.
 */

require '../include/imscp-lib.php';

check_login(__FILE__);

$cfg = iMSCP_Registry::get('config');

if (isset($_GET['id'])) {
	$ftp_acc = $_GET['id'];
} else if (isset($_POST['id'])) {
	$ftp_acc = $_POST['id'];
} else {
	user_goto('ftp_accounts.php');
}

$tpl = new iMSCP_pTemplate();
$tpl->define_dynamic('page', $cfg->CLIENT_TEMPLATE_PATH . '/ftp_edit.tpl');
$tpl->define_dynamic('page_message', 'page');
$tpl->define_dynamic('logged_from', 'page');

// page functions.

function gen_page_dynamic_data(&$tpl, &$sql, $ftp_acc) {

	$cfg = iMSCP_Registry::get('config');

	$query = "
		SELECT
			`homedir`
		FROM
			`ftp_users`
		WHERE
			`userid` = ?
	";

	$rs = exec_query($sql, $query, $ftp_acc);

	$homedir = $rs->fields['homedir'];
	$domain_ftp = $_SESSION['user_logged'];
	$nftp_dir = $cfg->FTP_HOMEDIR . "/" . $domain_ftp;

	if ($nftp_dir == $homedir) {
		$odir = '';
		$oins = '';
	} else {
		$odir = $cfg->HTML_CHECKED;
		$oins = substr($homedir, strlen($nftp_dir));
	}

	$tpl->assign(
		array(
			'FTP_ACCOUNT' => $ftp_acc,
			'ID' => $ftp_acc,
			'USE_OTHER_DIR_CHECKED' => $odir,
			'OTHER_DIR' => $oins
		)
	);
}

function update_ftp_account(&$sql, $ftp_acc, $dmn_name) {

	global $other_dir;
	$cfg = iMSCP_Registry::get('config');

	// Create a virtual filesystem (it's important to use =&!)
	$vfs = new iMSCP_VirtualFileSystem($dmn_name, $sql);

	if (isset($_POST['uaction']) && $_POST['uaction'] === 'edit_user') {
		if (!empty($_POST['pass']) || !empty($_POST['pass_rep'])) {
			if ($_POST['pass'] !== $_POST['pass_rep']) {
				set_page_message(tr('Entered passwords do not match!'), 'error');
				return;
			}
			if (!chk_password($_POST['pass'])) {
				if ($cfg->PASSWD_STRONG) {
					set_page_message(sprintf(tr('The password must be at least %s long and contain letters and numbers to be valid.'), $cfg->PASSWD_CHARS), 'error');
				} else {
					set_page_message(sprintf(tr('Password data is shorter than %s signs or includes not permitted signs!'), $cfg->PASSWD_CHARS), 'error');
				}
				return;
			}

			$pass = crypt_user_pass_with_salt($_POST['pass']);
			$rawpass = encrypt_db_password($_POST['pass']);
			if (isset($_POST['use_other_dir']) && $_POST['use_other_dir'] === 'on') {

				$other_dir = clean_input($_POST['other_dir']);

				$rs = $vfs->exists($other_dir);
				if (!$rs) {
					set_page_message(tr('%s does not exist', clean_input($_POST['other_dir'])), 'error');
					return;
				} // domain_id

				// append the full path (vfs is always checking per ftp so it's logged
				// in in the root of the user (no absolute paths are allowed here!)

				$other_dir = $cfg->FTP_HOMEDIR . "/" . $_SESSION['user_logged']
							. clean_input($_POST['other_dir']);

				$query = "
					UPDATE
						`ftp_users`
					SET
						`passwd` = ?,
						`rawpasswd` = ?,
						`homedir` = ?
					WHERE
						`userid` = ?
				";

				$rs = exec_query($sql, $query, array($pass, $rawpass, $other_dir, $ftp_acc));
			} else {
				$query = "
					UPDATE
						`ftp_users`
					SET
						`passwd` = ?,
						`rawpasswd` = ?
					WHERE
						`userid` = ?
				";
				$rs = exec_query($sql, $query, array($pass, $rawpass, $ftp_acc));
			}

			write_log($_SESSION['user_logged'] . ": updated FTP " . $ftp_acc . " account data");
			set_page_message(tr('FTP account data updated!'), 'success');
			user_goto('ftp_accounts.php');
		} else {
			if (isset($_POST['use_other_dir']) && $_POST['use_other_dir'] === 'on') {
				$other_dir = clean_input($_POST['other_dir']);
				// Strip possible double-slashes
				$other_dir = str_replace('//', '/', $other_dir);
				// Check for updirs ".."
				$res = preg_match("/\.\./", $other_dir);
				if ($res !== 0) {
					set_page_message(tr('Incorrect mount point length or syntax'), 'error');
					return;
				}
				$ftp_home = $cfg->FTP_HOMEDIR . "/$dmn_name/" . $other_dir;
				// Strip possible double-slashes
				$ftp_home = str_replace('//', '/', $other_dir);
				// Check for $other_dir existence
				// Create a virtual filesystem (it's important to use =&!)
				$vfs = new iMSCP_VirtualFileSystem($dmn_name, $sql);
				// Check for directory existence
				$res = $vfs->exists($other_dir);
				if (!$res) {
					set_page_message(tr('%s does not exist', $other_dir), 'error');
					return;
				}
				$other_dir = $cfg->FTP_HOMEDIR . "/" . $_SESSION['user_logged'] . $other_dir;
			} else { // End of user-specified mount-point

				$other_dir = $cfg->FTP_HOMEDIR . "/" . $_SESSION['user_logged'];

			}
			$query = "
				UPDATE
					`ftp_users`
				SET
					`homedir` = ?
				WHERE
					`userid` = ?
			";

			$rs = exec_query($sql, $query, array($other_dir, $ftp_acc));
			set_page_message(tr('FTP account data updated!'), 'success');
			user_goto('ftp_accounts.php');
		}
	}
}

// common page data.

$tpl->assign(
	array(
		'TR_CLIENT_EDIT_FTP_ACC_PAGE_TITLE' => tr('i-MSCP - Client/Edit FTP Account'),
		'THEME_COLOR_PATH' => "../themes/{$cfg->USER_INITIAL_THEME}",
		'THEME_CHARSET' => tr('encoding'),
		'ISP_LOGO' => get_logo($_SESSION['user_id'])
	)
);

// dynamic page data.


$query = "
	SELECT
		`domain_name`
	FROM
		`domain`
	WHERE
		`domain_admin_id` = ?
";

$rs = exec_query($sql, $query, $_SESSION['user_id']);

$dmn_name = $rs->fields['domain_name'];

if(!check_ftp_perms($ftp_acc)) {
    set_page_message(tr('User does not exist or you do not have permission to access this interface!'));
    user_goto('ftp_accounts.php');
}

gen_page_dynamic_data($tpl, $sql, $ftp_acc);
update_ftp_account($sql, $ftp_acc, $dmn_name);

// static page messages.

gen_client_mainmenu($tpl, $cfg->CLIENT_TEMPLATE_PATH . '/main_menu_ftp_accounts.tpl');
gen_client_menu($tpl, $cfg->CLIENT_TEMPLATE_PATH . '/menu_ftp_accounts.tpl');

gen_logged_from($tpl);

check_permissions($tpl);

$tpl->assign(
	array(
		'TR_EDIT_FTP_USER' 		=> tr('Edit FTP user'),
		'TR_FTP_ACCOUNT' 		=> tr('FTP account'),
		'TR_PASSWORD' 			=> tr('Password'),
		'TR_PASSWORD_REPEAT' 	=> tr('Repeat password'),
		'TR_USE_OTHER_DIR' 		=> tr('Use other dir'),
		'TR_EDIT' 				=> tr('Save changes'),
		'CHOOSE_DIR' 			=> tr('Choose dir'),
		// The entries below are for Demo versions only
		'PASSWORD_DISABLED'		=> tr('Password change is deactivated!'),
		'DEMO_VERSION'			=> tr('Demo Version!')
	)
);

generatePageMessage($tpl);

$tpl->parse('PAGE', 'page');
$tpl->prnt();

if ($cfg->DUMP_GUI_DEBUG) {
	dump_gui_debug();
}

unsetMessages();