
			<form name="sql_change_password_frm" method="post" action="sql_change_password.php">
				<table>
					<tr>
						<td style="width: 300px;"><label for="user_name">{TR_USER_NAME}</label></td>
						<td>
							<input id="user_name" type="text" name="user_name" value="{USER_NAME}" readonly="readonly" />
							@{SQL_USERS_HOSTNAME}
						</td>
					</tr>
					<tr>
						<td><label for="pass">{TR_PASS}</label></td>
						<td><input id="pass" type="password" name="pass" value="" autocomplete="off" /></td>
					</tr>
					<tr>
						<td><label for="pass_rep">{TR_PASS_REP}</label></td>
						<td><input id="pass_rep" type="password" name="pass_rep" value="" autocomplete="off" /></td>
					</tr>
				</table>
				<div class="buttons">
					<input name="Submit" type="submit" class="button" value="{TR_CHANGE}" />
				</div>
				<input type="hidden" name="uaction" value="change_pass" />
				<input type="hidden" name="id" value="{ID}" />
			</form>
