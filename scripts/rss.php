<?php
# Generates RSS feed for BBOX. Written by Ilya Zverev, licensed WTFPL.
require("db.inc.php");
require("lib.php");
$wkt;
$bbox_str;
if (isset($_REQUEST['wkt'])) {
    $wkt = $_REQUEST['wkt'];
    $bbox_str = $wkt;
} else if (isset($_REQUEST['bbox'])) {
    $bbox = parse_bbox($_REQUEST['bbox']);
    if ($bbox) {
        $wkt = get_wkt_from_bbox($bbox);
        $bbox_str = $bbox[0]*$tile_size.','.$bbox[1]*$tile_size.','.($bbox[2]+1)*$tile_size.','.($bbox[3]+1)*$tile_size;
        $bbox_str = "BBOX [$bbox_str]";
    }
}
if (!$wkt) {
    header(' ', true, 400);
    header('Content-type: plain/text');
    $file = basename(__FILE__);
    global $tile_size;
    $factor = 1 / $tile_size;
    print <<<EOT
Error: bbox or wkt required.

Supported arguments:
- bbox
- wkt
- user

Usage examples:
- $file?bbox=12,46,13,47
or equivalently (longutude and latitude multiplied by $factor)
- $file?wkt=POLYGON((4600 1200, 4700 1200, 4700 1300, 4600 1300, 4600 1200))
see also https://en.wikipedia.org/wiki/Well-known_text
EOT;
    exit;
}
header('Content-type: application/rss+xml; charset=utf-8');
$db = connect();
$bbox_query = get_bbox_query_for_wkt($wkt);
$user_query = get_user_query();
$sql = "select c.* from wdi_tiles t, wdi_changesets c where t.changeset_id = c.changeset_id $bbox_query $user_query group by c.changeset_id order by c.change_time desc limit 20";
$res = $db->query($sql);
$latlon = 'lat='.(($bbox[3]+$bbox[1])*$tile_size/2).'&amp;lon='.(($bbox[2]+$bbox[0])*$tile_size/2);
print <<<"EOT"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
\t<title>WhoDidIt Feed for $bbox_str</title>
\t<description>WhoDidIt feed for $bbox_str</description>
\t<link>$frontend_url?$latlon&amp;zoom=12</link>
\t<generator>WhoDidIt</generator>
\t<ttl>60</ttl>

EOT;
date_default_timezone_set('UTC');
while( $row = $res->fetch_assoc() ) {
    $susp = is_changeset_suspicious($row) ? '[!] ' : '';
    $untitled = !$row['comment'] || strlen($row['comment']) <= 2 || substr($row['comment'], 0, 5) == 'BBOX:';
    print "\t<item>\n";
    print "\t\t<title>${susp}".($untitled?'[untitled changeset]':htmlspecialchars($row['comment']))."</title>\n";
    print "\t\t<author>".htmlspecialchars($row['user_name'])."</author>\n";
    print "\t\t<link>https://www.openstreetmap.org/browse/changeset/${row['changeset_id']}#"."</link>\n";
    $date = strtotime($row['change_time']);
    $date_str = date(DATE_RSS, $date);
    print "\t\t<pubDate>$date_str</pubDate>\n";
    $desc = "<p>User <a href=\"https://www.openstreetmap.org/user/".rawurlencode($row['user_name'])."\">".htmlspecialchars($row['user_name'])."</a> has uploaded <a href=\"https://www.openstreetmap.org/browse/changeset/${row['changeset_id']}\">a changeset</a> in your watched area using ".htmlspecialchars($row['created_by']).", titled \"".htmlspecialchars($row['comment'])."\"</p>";
    $desc .= "<p>Show it <a href=\"$frontend_url?changeset=${row['changeset_id']}&show=1\">on WhoDidIt</a> or <a href=\"http://nrenner.github.io/achavi/?changeset=${row['changeset_id']}\">in Achavi</a>.</p>";
    $desc .= '<p>Statistics:<ul>';
    $desc .= '<li>Nodes: '.$row['nodes_created'].' created, '.$row['nodes_modified'].' modified, '.$row['nodes_deleted'].' deleted</li>';
    $desc .= '<li>Ways: '.$row['ways_created'].' created, '.$row['ways_modified'].' modified, '.$row['ways_deleted'].' deleted</li>';
    $desc .= '<li>Relations: '.$row['relations_created'].' created, '.$row['relations_modified'].' modified, '.$row['relations_deleted'].' deleted</li></ul></p>';
    print "\t\t<description>".htmlspecialchars($desc)."</description>\n";
    print "\t</item>\n";
}
print "</channel>\n</rss>";
