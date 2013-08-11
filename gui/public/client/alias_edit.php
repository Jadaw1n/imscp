<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 *
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
 *
 * Portions created by the ispCP Team are Copyright (C) 2006-2010 by
 * isp Control Panel. All Rights Reserved.
 *
 * Portions created by the i-MSCP Team are Copyright (C) 2010-2013 by
 * i-MSCP - internet Multi Server Control Panel. All Rights Reserved.
 *
 * @category	i-MSCP
 * @package		iMSCP_Core
 * @subpackage	Client
 * @copyright   2001-2006 by moleSoftware GmbH
 * @copyright   2006-2010 by ispCP | http://isp-control.net
 * @copyright   2010-2013 by i-MSCP | http://i-mscp.net
 * @author      ispCP Team
 * @author      i-MSCP Team
 * @link        http://i-mscp.net
 */

// Include core library
require_once 'imscp-lib.php';

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onClientScriptStart);

check_login('user');

customerHasFeature('domain_aliases') or showBadRequestErrorPage();

/** @var $cfg iMSCP_Config_Handler_File */
$cfg = iMSCP_Registry::get('config');

$tpl = new iMSCP_pTemplate();
$tpl->define_dynamic('layout', 'shared/layouts/ui.tpl');
$tpl->define_dynamic('page', 'client/alias_edit.tpl');
$tpl->define_dynamic('page_message', 'layout');

$tpl->assign(
	array(
		 'TR_PAGE_TITLE' => tr('Client / Domains / Overview / Edit Domain Alias'),
		 'ISP_LOGO' => layout_getUserLogo()));

$tpl->assign(
	array(
		'TR_ALIAS_NAME' => tr('Alias name'),
		'TR_DOMAIN_IP' => tr('Domain IP'),
		'TR_FORWARD' => tr('Forward to URL'),
		'TR_MOUNT_POINT' => tr('Mount point'),
		'TR_MODIFY' => tr('Modify'),
		'TR_CANCEL' => tr('Cancel'),
		'TR_ENABLE_FWD' => tr("Enable Forward"),
		'TR_ENABLE' => tr("Enable"),
		'TR_DISABLE' => tr("Disable"),
		'TR_PREFIX_HTTP' => 'http://',
		'TR_PREFIX_HTTPS' => 'https://',
		'TR_PREFIX_FTP' => 'ftp://',
		'TR_DOMAIN_ALIAS_DATA' => tr('Domain alias data')));

generateNavigation($tpl);

// "Modify" button has been pressed
if (isset($_POST['uaction']) && ($_POST['uaction'] == 'modify')) {
	if (isset($_GET['edit_id'])) {
		$editid = $_GET['edit_id'];
	} else if (isset($_SESSION['edit_ID'])) {
		$editid = $_SESSION['edit_ID'];
	} else {
		unset($_SESSION['edit_ID']);

		//$_SESSION['aledit'] = '_no_';
		showBadRequestErrorPage();
	}

	// Save data to db
	if (check_fwd_data($tpl, $editid)) {
		//$_SESSION['aledit'] = "_yes_";
		set_page_message(tr('Domain alias scheduled for update.'), 'success');
		redirectTo('domains_manage.php');
	}
} else {
	// Get user id that comes for edit
	if (isset($_GET['edit_id'])) {
		$editid = $_GET['edit_id'];
	}

	$_SESSION['edit_ID'] = $editid;
}

gen_editalias_page($tpl, $editid);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onClientScriptEnd, array('templateEngine' => $tpl));

$tpl->prnt();

unsetMessages();


/**
 * @param iMSCP_pTemplate $tpl Template engine
 * @param int $edit_id
 * @return void
 */
function gen_editalias_page(&$tpl, $edit_id) {

	/** @var $cfg iMSCP_Config_Handler_File */
	$cfg = iMSCP_Registry::get('config');

	// Get data from sql
	$domainProps = get_domain_default_props($_SESSION['user_id']);
    $domain_id = $domainProps['domain_id'];

	$res = exec_query("SELECT * FROM `domain_aliasses` WHERE `alias_id` = ? AND `domain_id` = ?", array($edit_id, $domain_id));

	if ($res->recordCount() <= 0) {
		$_SESSION['aledit'] = '_no_';
		redirectTo('domains_manage.php');
	}
	$data = $res->fetchRow();
	// Get IP data
	$ipres = exec_query("SELECT * FROM `server_ips` WHERE `ip_id` = ?", $data['alias_ip_id']);
	$ipdat = $ipres->fetchRow();
	$ip_data = $ipdat['ip_number'] . ' (' . $ipdat['ip_alias'] . ')';

	if (isset($_POST['uaction']) && ($_POST['uaction'] == 'modify')) {
		$url_forward = strtolower(clean_input($_POST['forward']));
	} else {
		$url_forward = decode_idna(preg_replace("(ftp://|https://|http://)", "", $data['url_forward']));

		if ($data["url_forward"] == "no") {
			$check_en = '';
			$check_dis = $cfg->HTML_CHECKED;
			$url_forward = '';
			$tpl->assign(
				array(
					'READONLY_FORWARD'	=> $cfg->HTML_READONLY,
					'DISABLE_FORWARD'	=> $cfg->HTML_DISABLED,
					'HTTP_YES'			=> '',
					'HTTPS_YES'			=> '',
					'FTP_YES'			=> ''
				)
			);
		} else {
			$check_en = $cfg->HTML_CHECKED;
			$check_dis = '';
			$tpl->assign(
				array(
					'READONLY_FORWARD'	=> '',
					'DISABLE_FORWARD'	=> '',
					'HTTP_YES'			=> (preg_match("/http:\/\//", $data['url_forward'])) ? $cfg->HTML_SELECTED : '',
					'HTTPS_YES'			=> (preg_match("/https:\/\//", $data['url_forward'])) ? $cfg->HTML_SELECTED : '',
					'FTP_YES'			=> (preg_match("/ftp:\/\//", $data['url_forward'])) ? $cfg->HTML_SELECTED : ''
				)
			);
		}
		$tpl->assign(
			array(
				'CHECK_EN' => $check_en,
				'CHECK_DIS' => $check_dis
			)
		);
	}
	// Fill in the fields
	$tpl->assign(
		array(
			'ALIAS_NAME' => tohtml(decode_idna($data['alias_name'])),
			'DOMAIN_IP' => $ip_data,
			'FORWARD' => tohtml($url_forward),
			'MOUNT_POINT' => tohtml($data['alias_mount']),
			'ID' => $edit_id
		)
	);
} // End of gen_editalias_page()

/**
 * Check input data
 *
 * @param iMSCP_pTemplate $tpl Template engine
 * @param int $alias_id
 * @return bool
 */
function check_fwd_data($tpl, $alias_id) {

	/** @var $cfg iMSCP_Config_Handler_File */
	$cfg = iMSCP_Registry::get('config');

	if (isset($_POST['status']) && $_POST['status'] == 1) {

		$forward_prefix = clean_input($_POST['forward_prefix']);
		$forward = strtolower(clean_input($_POST['forward']));
        $aurl = @parse_url($forward_prefix . $forward);

        if ($aurl === false) {
            set_page_message(tr('Wrong address in forward URL.'), 'error');
        } else {
            $domain = $aurl['host'];

            if (substr_count($domain, '.') <= 2) {
                $ret = validates_dname($domain);
            } else {
                $ret = validates_dname($domain, true);
            }

            if (!$ret) {
                set_page_message(tr('Wrong domain part in forward URL.', 'error'));
            } else {
                $domain = encode_idna($aurl['host']);
                $forward = $aurl['scheme'] . '://';

                if (isset($aurl['user'])) {
                    $forward .= $aurl['user'] . (isset($aurl['pass']) ? ':' . $aurl['pass'] : '') . '@';
                }

                $forward .= $domain;

                if (isset($aurl['port'])) {
                    $forward .= ':' . $aurl['port'];
                }

                if (isset($aurl['path'])) {
                    $forward .= $aurl['path'];
                } else {
                    $forward .= '/';
                }

                if (isset($aurl['query'])) {
                    $forward .= '?' . $aurl['query'];
                }

                if (isset($aurl['fragment'])) {
                    $forward .= '#' . $aurl['fragment'];
                }
            }
        }

		$check_en = $cfg->HTML_CHECKED;
		$check_dis = '';
		$tpl->assign(
			array(
				'FORWARD'			=> tohtml($forward),
				'HTTP_YES'			=> ($forward_prefix === 'http://') ? $cfg->HTML_SELECTED : '',
				'HTTPS_YES'			=> ($forward_prefix === 'https://') ? $cfg->HTML_SELECTED : '',
				'FTP_YES'			=> ($forward_prefix === 'ftp://') ? $cfg->HTML_SELECTED : '',
				'CHECK_EN'			=> $check_en,
				'CHECK_DIS'			=> $check_dis,
				'DISABLE_FORWARD'	=>	'',
				'READONLY_FORWARD'	=>	''
			)
		);
	} else {
		$check_en = '';
		$check_dis = $cfg->HTML_CHECKED;
		$forward = 'no';
		$tpl->assign(
			array(
				'READONLY_FORWARD' => $cfg->HTML_READONLY,
				'DISABLE_FORWARD' => $cfg->HTML_DISABLED,
				'CHECK_EN' => $check_en,
				'CHECK_DIS' => $check_dis,
			)
		);
	}

	if (!Zend_Session::namespaceIsset('pageMessages')) {

		iMSCP_Events_Manager::getInstance()->dispatch(
			iMSCP_Events::onBeforeEditDomainAlias, array('domainAliasId' => $alias_id)
		);

		$query = "UPDATE `domain_aliasses` SET `url_forward` = ?, `alias_status` = ? WHERE `alias_id` = ?";
		exec_query($query, array($forward, $cfg->ITEM_TOCHANGE_STATUS, $alias_id));

		$query = "UPDATE `subdomain_alias` SET `subdomain_alias_status` = ? WHERE `alias_id` = ?";
		exec_query($query, array($cfg->ITEM_TOCHANGE_STATUS, $alias_id));

		iMSCP_Events_Manager::getInstance()->dispatch(
			iMSCP_Events::onAfterEditDomainALias, array('domainAliasId' => $alias_id)
		);

		send_request();

		$admin_login = $_SESSION['user_logged'];

		$rs = exec_query("SELECT `alias_name` FROM `domain_aliasses` WHERE `alias_id` = ?", $alias_id );

		write_log("$admin_login: change domain alias forward: " . $rs->fields['alias_name'], E_USER_NOTICE);
		unset($_SESSION['edit_ID']);
		return true;

	} else {
		return false;
	}
} // End of check_user_data()
