<?php
function get_changeset_query() {
    if (!isset($_REQUEST['changeset']))
        return '';
    $in_notin = group_in_notin($_REQUEST['changeset']);
    if (!$in_notin)
        return '';
    $changesets_in = $in_notin['in'];
    $changesets_notin = $in_notin['notin'];
    $changesets = '';
    if (count($changesets_in))
        $changesets .= ' and t.changeset_id in (' . implode(',', array_map('intval', $changesets_in)) . ')';
    if (count($changesets_notin))
        $changesets .= ' and t.changeset_id not in (' . implode(',', array_map('intval', $changesets_notin)) . ')';
    return $changesets;
}

function get_user_query() {
    if (!isset($_REQUEST['user']))
        return '';
    $in_notin = group_in_notin($_REQUEST['user']);
    if (!$in_notin)
        return '';
    $usernames_in = $in_notin['in'];
    $usernames_notin = $in_notin['notin'];
    $user = '';
    if (count($usernames_in))
        $user .= " and c.user_name in ('" . implode("','", array_map('db_escape_string', $usernames_in)) . "')";
    if (count($usernames_notin))
        $user .= " and c.user_name not in ('" . implode("','", array_map('db_escape_string', $usernames_notin)) . "')";
    return $user;
}

function group_in_notin($request_parameter) {
    if (isset($request_parameter) && strlen($request_parameter) > 0) {
        $usernames = preg_split('/\\s*,\\s*/', $request_parameter);
        $usernames_in = array();
        $usernames_notin = array();
        foreach ($usernames as $u) {
            if ($u[0] == '!' || $u[0] == '-')
                $usernames_notin[] = substr($u, 1);
            else
                $usernames_in[] = $u;
        }
        return array('in' => $usernames_in, 'notin' => $usernames_notin);
    } else {
        return null;
    }
}

function get_editor_query() {
    return isset($_REQUEST['editor']) && strlen($_REQUEST['editor']) > 0 ? ' and c.created_by like \'%'.db_escape_string($_REQUEST['editor']).'%\'' : '';
}

function parse_bbox( $bbox_str ) {
    global $tile_size;
    if( !preg_match('/^-?[\d.]+(,-?[\d.]+){3}$/', $bbox_str) ) return 0;
    $bbox = explode(',', $bbox_str);
    for( $i = 0; $i < 4; $i++ )
        $bbox[$i] = floor($bbox[$i]/$tile_size);
    if( $bbox[2] < $bbox[0] ) { $t = $bbox[2]; $bbox[2] = $bbox[0]; $bbox[0] = $t; }
    if( $bbox[3] < $bbox[1] ) { $t = $bbox[3]; $bbox[3] = $bbox[1]; $bbox[1] = $t; }
    return $bbox;
}

function get_bbox_query($bbox) {
    return get_bbox_query_for_wkt(get_wkt_from_bbox($bbox));
}

function get_wkt_from_bbox($bbox) {
    return "POLYGON(($bbox[1] $bbox[0], $bbox[3] $bbox[0], $bbox[3] $bbox[2], $bbox[1] $bbox[2], $bbox[1] $bbox[0]))";
}

function get_bbox_query_for_wkt($wkt) {
    $wkt = db_escape_string($wkt);
    return " AND ST_Contains(ST_GeomFromText('$wkt'), latlon)";
}
