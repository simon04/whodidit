<? # Some useful functions for whodidit scripts. Written by Ilya Zverev, licensed WTFPL.
$tile_size = 0.01;
$frontend_url = 'http://localhost/wdi/index.html';

function connect() {
    # host, user, password, database
    $db = new mysqli('localhost', 'wdi', '', 'wdi');
    $db->set_charset('utf8');
    return $db;
}

function db_escape_string($str) {
    global $db;
    return $db->escape_string($str);
}

function is_changeset_suspicious( $ch ) {
    // more than 30% of node or way deletions (allow 11 and 6)
    if( $ch['nodes_deleted'] > $ch['nodes_modified'] + $ch['nodes_created'] + 10 ) return true;
    if( $ch['ways_deleted'] > $ch['ways_modified'] + $ch['ways_created'] + 5 ) return true;
    // more relations deleted than created (allow 3)
    if( $ch['relations_deleted'] > $ch['relations_created'] + 2 ) return true;
    // mass-change/deletion
    if( $ch['nodes_modified'] + $ch['nodes_deleted'] + $ch['ways_modified'] + $ch['ways_deleted'] > 5000 ) return true;
    if( $ch['relations_modified'] + $ch['relations_deleted'] > 40 ) return true;
    // potlatch + relations modified or deleted
    if( strpos($ch['created_by'], 'Potlatch') !== FALSE && $ch['relations_modified'] + $ch['relations_deleted'] > 0 ) return true;
    // well, seems normal
    return false;
}
?>
