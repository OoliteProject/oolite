<!DOCTYPE html>
<html>
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Oolite nightly (Mac&nbsp;OS&nbsp;X)</title>
</head>
<body>

<p>
<?php
	$latest_name = rtrim(file_get_contents("latest"));
	$latest_date = rtrim(file_get_contents("last_updated"));
	
	print "<a href=\"$latest_name\">$latest_name</a> ($latest_date)";
?>
</p>

<h3>Changes since last nightly</h3>
<p style="font-family: monospace">
<?php
	$change_log = nl2br(htmlspecialchars(file_get_contents("change_log")));
	
	print $change_log;
	?>
</p>

</body>
</html>
