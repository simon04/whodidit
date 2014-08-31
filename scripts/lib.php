<?
function get_user_query() {
    if (isset($_REQUEST['user']) && strlen($_REQUEST['user']) > 0) {
        $usernames = preg_split('/\\s*,\\s*/', $_REQUEST['user']);
        $usernames_in = array();
        $usernames_notin = array();
        foreach ($usernames as $u) {
            if ($u[0] == '!' || $u[0] == '-')
                $usernames_notin[] = substr($u, 1);
            else
                $usernames_in[] = $u;
        }
        $aggregate = true;
        $user = '';
        if (count($usernames_in))
            $user .= " and c.user_name in ('" . implode("','", array_map('db_escape_string', $usernames_in)) . "')";
        if (count($usernames_notin))
            $user .= " and c.user_name not in ('" . implode("','", array_map('db_escape_string', $usernames_notin)) . "')";
    } else
        $user = '';
    return $user;
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
    return " AND Contains(GeomFromText('$wkt'), latlon)";
}

?>
