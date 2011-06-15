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

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onClientScriptStart);

check_login(__FILE__);

$cfg = iMSCP_Registry::get('config');

$tpl = new iMSCP_pTemplate();
$tpl->define_dynamic('page', $cfg->CLIENT_TEMPLATE_PATH . '/sql_change_password.tpl');
$tpl->define_dynamic('page_message', 'page');
$tpl->define_dynamic('logged_from', 'page');

if (isset($_GET['id'])) {
	$db_user_id = $_GET['id'];
} else if (isset($_POST['id'])) {
	$db_user_id = $_POST['id'];
} else {
	user_goto('sql_manage.php');
}

// page functions.
function change_sql_user_pass($db_user_id, $db_user_name) {

	$cfg = iMSCP_Registry::get('config');

	if (!isset($_POST['uaction'])) {
		return;
	}

	if ($_POST['pass'] === '' && $_POST['pass_rep'] === '') {
		set_page_message(tr('Please type user password!'), 'error');
		return;
	}

	if ($_POST['pass'] !== $_POST['pass_rep']) {
		set_page_message(tr('Entered passwords do not match!'), 'error');
		return;
	}

	if (strlen($_POST['pass']) > $cfg->MAX_SQL_PASS_LENGTH) {
		set_page_message(tr('Too long user password!'), 'error');
		return;
	}

	if (isset($_POST['pass'])
		&& !preg_match('/^[[:alnum:]:!\*\+\#_.-]+$/', $_POST['pass'])) {
		set_page_message(tr('Don\'t use special chars like "@, $, %..." in the password!'), 'error');
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

	$user_pass = $_POST['pass'];

	// update user pass in the i-MSCP sql_user table;
	$query = "
		UPDATE
			`sql_user`
		SET
			`sqlu_pass` = ?
		WHERE
			`sqlu_name` = ?
	";
	exec_query($query, array($user_pass, $db_user_name));

	// update user pass in the mysql system tables;
	// TODO use prepared statement for $user_pass
	$query = "SET PASSWORD FOR '$db_user_name'@'%' = PASSWORD('$user_pass')";

	execute_query($query);
	// TODO use prepared statement for $user_pass
	$query = "SET PASSWORD FOR '$db_user_name'@localhost = PASSWORD('$user_pass')";
	execute_query($query);

	write_log($_SESSION['user_logged'] . ": update SQL user password: " . tohtml($db_user_name));
	set_page_message(tr('SQL user password was successfully changed!'), 'success');
	user_goto('sql_manage.php');
}

function gen_page_data(&$tpl, $db_user_id) {

	$query = "
		SELECT
			`sqlu_name`
		FROM
			`sql_user`
		WHERE
			`sqlu_id` = ?
	";

	$rs = exec_query($query, $db_user_id);
	$tpl->assign(
		array(
			'USER_NAME' => tohtml($rs->fields['sqlu_name']),
			'ID' => $db_user_id
		)
	);
	return $rs->fields['sqlu_name'];
}

// common page data.

if (isset($_SESSION['sql_support']) && $_SESSION['sql_support'] == "no") {
	user_goto('index.php');
}

$tpl->assign(
	array(
		'TR_CLIENT_SQL_CHANGE_PASSWORD_PAGE_TITLE' => tr('i-MSCP - Client/Change SQL User Password'),
		'THEME_COLOR_PATH' => "../themes/{$cfg->USER_INITIAL_THEME}",
		'THEME_CHARSET' => tr('encoding'),
		'ISP_LOGO' => get_logo($_SESSION['user_id'])
	)
);

$db_user_name = gen_page_data($tpl, $db_user_id);

if(!check_user_sql_perms($db_user_id))
{
    set_page_message(tr('User does not exist or you do not have permission to access this interface.'));
    user_goto('sql_manage.php');
}

check_user_sql_perms($db_user_id);
change_sql_user_pass($db_user_id, $db_user_name);


gen_client_mainmenu($tpl, $cfg->CLIENT_TEMPLATE_PATH . '/main_menu_manage_sql.tpl');
gen_client_menu($tpl, $cfg->CLIENT_TEMPLATE_PATH . '/menu_manage_sql.tpl');
gen_logged_from($tpl);
check_permissions($tpl);

$tpl->assign(
	array(
		'TR_CHANGE_SQL_USER_PASSWORD' 	=> tr('Change SQL user password'),
		'TR_USER_NAME' 					=> tr('User name'),
		'TR_PASS' 						=> tr('Password'),
		'TR_PASS_REP' 					=> tr('Repeat password'),
		'TR_CHANGE' 					=> tr('Change'),
		// The entries below are for Demo versions only
		'PASSWORD_DISABLED'				=> tr('Password change is deactivated!'),
		'DEMO_VERSION'					=> tr('Demo Version!')
	)
);

generatePageMessage($tpl);
$tpl->parse('PAGE', 'page');

iMSCP_Events_Manager::getInstance()->dispatch(
    iMSCP_Events::onClientScriptEnd, new iMSCP_Events_Response($tpl));

$tpl->prnt();

unsetMessages();