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
            $user .= " and c.user_name in ('" . implode("','", array_map($db->escape_string, $usernames_in)) . "')";
        if (count($usernames_notin))
            $user .= " and c.user_name not in ('" . implode("','", array_map($db->escape_string, $usernames_notin)) . "')";
    } else
        $user = '';
    return $user;
}

function get_bbox_query($bbox) {
    return " AND Contains(GeomFromText('POLYGON(($bbox[1] $bbox[0], $bbox[3] $bbox[0], $bbox[3] $bbox[2], $bbox[1] $bbox[2], $bbox[1] $bbox[0]))'), latlon)";
}

?>
