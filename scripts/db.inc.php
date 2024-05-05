<?php
require('config.inc.php');
function connect() {
    global $db_hostname, $db_username, $db_password, $db_database;
    $db = new mysqli($db_hostname, $db_username, $db_password, $db_database);
    $db->set_charset('utf8');
    return $db;
}
