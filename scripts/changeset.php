<?php
# Returns json with complete data for specified changesets. Written by Ilya Zverev, licensed WTFPL.
header('Content-type: application/json; charset=utf-8');
require('db.inc.php');
$latest = isset($_REQUEST['latest']) && $_REQUEST['latest'] == '1';
$id = isset($_REQUEST['id']) && preg_match('/^[\d,]+$/', $_REQUEST['id']) ? $_REQUEST['id'] : 0;
if( !$latest && !$id ) {
    print '{ "error" : "id required"}';
    exit;
}
$db = connect();
if( $latest ) {
    $where = '1=1 order by change_time desc limit 1';
} elseif( strpos($id, ',') === FALSE ) {
    $where = 'changeset_id = '.$_REQUEST['id'];
} else {
    $where = 'changeset_id in ('.$_REQUEST['id'].') order by change_time desc';
}

$res = $db->query('select * from wdi_changesets where '.$where);
print '[';
$first = true;
while( $row = $res->fetch_assoc() ) {
    if( $first ) $first = false; else print ",\n";
    $row['suspicious'] = is_changeset_suspicious($row) ? 1 : 0;
    print json_encode($row);
}
print ']';
