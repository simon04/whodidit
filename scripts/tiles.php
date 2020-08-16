<?php
# Returns all tiles inside a bbox, possibly filtered. Written by Ilya Zverev, licensed WTFPL.
require("db.inc.php");
require("lib.php");
header('Content-type: application/json; charset=utf-8');
if( strstr($_SERVER['HTTP_USER_AGENT'], 'MSIE') == false ) {
    header('Expires: Fri, 01 Jan 2010 05:00:00 GMT');
    header('Cache-Control: no-cache, must-revalidate');
    header('Pragma: no-cache');
} else {
    header('Cache-Control: no-cache');
    header('Expires: -1');
}
$small_tile_limit = 6000; // bbox requested must contain no more than this much tiles
$aggregate_tile_limit = $small_tile_limit * 100; // in some cases it is allowed to contain this much
$db_tile_limit = 1000; // if there are this much tiles in DB, return error
$aggregate_db_limit = 400; // if there are less than this much DB tiles in bbox, allow aggregate tiles
$aggregate_only_filtered = true; // show aggregate tiles only when filtered by a user or a changeset

$extent = isset($_REQUEST['extent']) && $_REQUEST['extent'] = '1';
$bbox = parse_bbox(isset($_REQUEST['bbox']) ? $_REQUEST['bbox'] : '');
$tile_count = ($bbox[2]-$bbox[0]) * ($bbox[3]-$bbox[1]);
if( !$bbox && !$extent ) {
    print '{ "error" : "BBox required" }';
    exit;
}

$aggregate = false;
$db = connect();
$changeset = get_changeset_query();
if( strlen($changeset) > 0 ) $aggregate = true;
//$age = isset($_REQUEST['age']) && preg_match('/^\d+$/', $_REQUEST['age']) ? $_REQUEST['age'] : 7;
if (isset($_REQUEST['age']) && is_numeric($_REQUEST['age']))
    $age = ($_REQUEST['age'] . ' day');
else if (isset($_REQUEST['age']) && preg_match('/^\d+\s+(minute|hour|day|week|month|quarter|year)\s*/i', $_REQUEST['age']))
    $age = $_REQUEST['age'];
else
    $age = '7 day';
$age_sql = $changeset && strpos($changeset, 'not in') === FALSE ? '' : " AND t.change_time > Date_sub(UTC_TIMESTAMP(), INTERVAL $age)";
$bbox_query = $extent ? '' : get_bbox_query($bbox);
$editor = get_editor_query();
$user = get_user_query();

if( $aggregate && !$aggregate_only_filtered && isset($aggregate_db_limit) && $aggregate_db_limit > 0 ) {
    $test_sql = "select 1 from ${dbprefix}tiles t, ${dbprefix}changesets c where c.changeset_id = t.changeset_id".
        $bbox_query.
        $age_sql.
        $user.
        $editor.
        $changeset.
        ' limit '.$aggregate_db_limit;
    $tres = $db->query($test_sql);
    $aggregate = $tres->num_rows < $aggregate_db_limit;
}

$tile_limit = $aggregate ? $aggregate_tile_limit : $small_tile_limit;
if( $tile_count > $tile_limit ) {
    print "{ \"error\" : \"Area is too large, please zoom in (requested: $tile_count, max: $tile_limit)\" }";
    exit;
}

if( $extent ) {
    // write bbox and exit
    $sql = "select min(t.lon), min(t.lat), max(t.lon), max(t.lat) from ${dbprefix}tiles t, ${dbprefix}changesets c where c.changeset_id = t.changeset_id".$age_sql.$user.$changeset;
    $res = $db->query($sql);
    if( $res === FALSE || $res->num_rows == 0 ) {
        print '{ "error" : "Cannot determine bounds" }';
        exit;
    }
    $row = $res->fetch_array();
    print '[';
    if( !$row[0] && !$row[3] ) {
        print '"no results"';
    } else {
        for( $i = 0; $i < 4; $i++ ) {
            print ($row[$i] + ($i < 2 ? 0 : 1)) * $tile_size;
            if( $i < 3 ) print ', ';
        }
    }
    print ']';
    exit;
}

if( $tile_count <= $small_tile_limit ) {
    $sql = 'select t.lat as rlat, t.lon as rlon';
} else {
    $sql = 'select floor(t.lat/10) as rlat, floor(t.lon/10) as rlon';
    $tile_size *= 10;
}
$sql .= ', Substring_index(Group_concat(t.changeset_id ORDER BY t.changeset_id DESC SEPARATOR \',\'), \',\', 10) as changesets';
$sql .= ', sum(t.nodes_created) as nc';
$sql .= ', sum(t.nodes_modified) as nm';
$sql .= ', sum(t.nodes_deleted) as nd';
$sql .= " from ${dbprefix}tiles t";
$sql .= ", ${dbprefix}changesets c";
$sql .= ' where c.changeset_id = t.changeset_id';
$sql .= $bbox_query;
$sql .= $age_sql;
$sql .= $user;
$sql .= $editor;
$sql .= $changeset;
$sql .= ' group by rlat, rlon limit '.($db_tile_limit+1);

$res = $db->query($sql);
if (!$res) {
    die($db->error);
} else if( $res->num_rows > $db_tile_limit ) {
    print '{ "error" : "Too many tiles to display, please zoom in" }';
    exit;
}

print '{ "type" : "FeatureCollection", "features" : ['."\n";
$first = true;
while( $row = $res->fetch_assoc() ) {
    if( !$first ) print ",\n"; else $first = false;
    $lon = $row['rlon'] * $tile_size;
    $lat = $row['rlat'] * $tile_size;
    $poly = array( array($lon, $lat), array($lon+$tile_size, $lat), array($lon+$tile_size, $lat+$tile_size), array($lon, $lat+$tile_size), array($lon, $lat) );
    $changesets = $row['changesets'];
    if( substr_count($changesets, ',') >= 10 ) {
        $changesets = implode(',', array_slice(explode(',', $changesets), 0, 10));
    }
    $feature = array(
        'type' => 'Feature',
        'geometry' => array(
            'type' => 'Polygon',
            'coordinates' => array($poly)
        ),
        'properties' => array(
            'changesets' => $changesets,
            'nodes_created' => $row['nc'],
            'nodes_modified' => $row['nm'],
            'nodes_deleted' => $row['nd']
        )
    );
    print json_encode($feature);
}
print "\n] }";
