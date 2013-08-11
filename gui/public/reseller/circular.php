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
 * @category    i-MSCP
 * @package     iMSCP_Core
 * @subpackage  Reseller
 * @copyright   2001-2006 by moleSoftware GmbH
 * @copyright   2006-2010 by ispCP | http://isp-control.net
 * @copyright   2010-2013 by i-MSCP | http://i-mscp.net
 * @author      ispCP Team
 * @author      i-MSCP Team
 * @link        http://i-mscp.net
 */

/***********************************************************************************************************************
 * TODO: Using the PHP mail function to send mass emails is an error (as stated by the PHP documentation).
 * We must solve this by using a specific library such as phpmailer that is really more efficient in such context.
 */

/***********************************************************************************************************************
 * Functions
 */

/**
 * Send the given email.
 *
 * @param string $to receivers of the mail
 * @param string $from Sender of the mail
 * @param string $subject Message subject
 * @param string $message Message body
 * @return void
 */
function sendEmail($to, $from, $subject, $message)
{
	$headers = "MIME-Version: 1.0\r\n";
	$headers .= "Content-Type: text/plain; charset=utf-8\r\n";
	$headers .= "Content-Transfer-Encoding: 8bit\r\n";
	$headers .= "From: $from\r\n";
	$headers .= "X-Mailer: i-MSCP mailer\r\n";

	mail($to, $subject, $message, $headers);
}

/**
 * Send email to all customers of the given reseller.
 *
 * @param int $resellerId Reseller unique identifier
 * @return void
 */
function sendEmailToResellerCustomers($resellerId)
{
	global $messageSubject, $messageBody,  $senderName, $senderEmail;

	$query = '
		SELECT
			`admin_name`, `fname`, `lname`, `email`
		FROM
			`admin`
		WHERE
			`admin_type` = ?
		AND
			`created_by` = ?
		GROUP BY
			`email`
	';
	$stmt = exec_query($query, array('user', $resellerId));

	while (!$stmt->EOF) {
		if($stmt->fields['fname'] == '' &&  $stmt->fields['lname'] == '') {
			$to = encode(decode_idna($stmt->fields['admin_name']));
		} else {
			$to = trim("{$stmt->fields['fname']} {$stmt->fields['lname']}");
		}

		$to = encode($to . "<{$stmt->fields['email']}>");
		$from = encode(trim($senderName)) . " <$senderEmail>";

		sendEmail($to, $from, encode($messageSubject), $messageBody);
		$stmt->moveNext();
	}
}

/**
 * Check email data.
 *
 * @return bool TRUE if all data are valid, FALSE otherwise
 */
function checkEmailData()
{
	global $messageSubject, $messageBody, $senderEmail, $senderName;

	if(
		isset($_POST['rcpt_to']) && isset($_POST['msg_subject']) && isset($_POST['msg_text']) &&
		isset($_POST['sender_email']) && isset($_POST['sender_name'])
	) {

		$messageSubject = clean_input($_POST['msg_subject'], false);
		$messageBody = clean_input($_POST['msg_text'], false);
		$senderEmail = clean_input($_POST['sender_email'], false);
		$senderName =  clean_input($_POST['sender_name'], false);

		if ($messageSubject == '') {
			set_page_message(tr('Message subject is missing.'), 'error');
		}

		if ($messageBody == '') {
			set_page_message(tr('Message body is missing.'), 'error');
		}

		if ($senderName == '') {
			set_page_message(tr('Sender name is missing.'), 'error');
		}

		if ($senderEmail == '') {
			set_page_message(tr('Sender email is missing.'), 'error');
		} elseif (!chk_email($senderEmail)) {
			set_page_message(tr("Incorrect email length or syntax."), 'error');
		}

		if (Zend_Session::namespaceIsset('pageMessages')) {
			return false;
		}

		return true;
	} else {
		showBadRequestErrorPage();
		exit;
	}
}

/**
 * Generate page  data.
 *
 * @param iMSCP_pTemplate $tpl
 * @return void
 */
function generatePageData($tpl)
{
	global $messageSubject, $messageBody, $senderEmail, $senderName;

	if (isset($_POST['uaction']) && $_POST['uaction'] === 'send_circular') {
		$tpl->assign(
			array(
				'MESSAGE_SUBJECT' => tohtml($messageSubject),
				'MESSAGE_TEXT' => tohtml($messageBody),
				'SENDER_EMAIL' => tohtml($senderEmail),
				'SENDER_NAME' => tohtml($senderName)
			)
		);
	} else {
		$query = 'SELECT `admin_name`, `fname`, `lname`, `email` FROM `admin` WHERE `admin_id` = ?';
		$stmt = exec_query($query, $_SESSION['user_id']);
		$data = $stmt->fetchRow();

		if (!empty($data['fname']) && !empty($data['lname'])) {
			$senderName = $data['fname'] . ' ' . $data['lname'];
		} elseif (!empty($data['fname'])) {
			$senderName = $stmt->fields['fname'];
		} elseif (!empty($data['lname'])) {
			$senderName = $stmt->fields['lname'];
		} else {
			$senderName = $data['admin_name'];
		}

		$tpl->assign(
			array(
				'MESSAGE_SUBJECT' => '',
				'MESSAGE_TEXT' => '',
				'SENDER_EMAIL' => tohtml($data['email']),
				'SENDER_NAME' => tohtml($senderName)
			)
		);
	}
}

/**
 * Send circular.
 *
 * @return void
 */
function sendCircular()
{
	global $senderName, $senderEmail;

	if (isset($_POST['uaction']) && $_POST['uaction'] == 'send_circular' && isset($_POST['rcpt_to'])) {
		if (checkEmailData()) {
			sendEmailToResellerCustomers($_SESSION['user_id']);
			set_page_message(tr('Mass email successfully sent.'), 'success');
			write_log('Mass email has been sent from Reseller ' . tohtml("$senderName <$senderEmail"), E_USER_NOTICE);
			redirectTo('users.php');
		}
	}
}

/***********************************************************************************************************************
 * Main
 */

// Include core library
require 'imscp-lib.php';

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onResellerScriptStart);

check_login('reseller');

if(!resellerHasCustomers()) {
	showBadRequestErrorPage();
}

$tpl = new iMSCP_pTemplate();
$tpl->define_dynamic(
	array(
		'layout' => 'shared/layouts/ui.tpl',
		'page' => 'reseller/circular.tpl',
		'page_message' => 'layout'
	)
);

$tpl->assign(
	array(
		'TR_PAGE_TITLE' => tr('Reseller / Customers / Circular'),
		'ISP_LOGO' => layout_getUserLogo(),
		'TR_CIRCULAR' => tr('Circular'),
		'TR_MESSAGE_SUBJECT' => tr('Message subject'),
		'TR_MESSAGE_TEXT' => tr('Message body'),
		'TR_SENDER_EMAIL' => tr('Sender email'),
		'TR_SENDER_NAME' => tr('Sender name'),
		'TR_SEND_MESSAGE' => tr('Send message')
	)
);

sendCircular();
generateNavigation($tpl);
generatePageData($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');

iMSCP_Events_Manager::getInstance()->dispatch(iMSCP_Events::onResellerScriptEnd, array('templateEngine' => $tpl));

$tpl->prnt();

unsetMessages();
