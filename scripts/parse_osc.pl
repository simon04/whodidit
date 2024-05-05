#!/usr/bin/env perl

# This tool either processes a single osc file or downloads replication osc base on state file.
# The result is inserted into whodidit database.
# Written by Ilya Zverev, licensed WTFPL.

use strict;
use Getopt::Long;
use File::Basename;
use LWP::Simple;
use IO::Uncompress::Gunzip;
use DBIx::Simple;
use XML::LibXML::Reader qw( XML_READER_TYPE_ELEMENT XML_READER_TYPE_END_ELEMENT );
use POSIX;
use Devel::Size qw(total_size);
use Time::HiRes qw(gettimeofday tv_interval);
use Cwd qw(abs_path);

my $wget = `/usr/bin/which wget` || 'wget';
$wget =~ s/\s//s;
my $state_file = dirname(abs_path(__FILE__)).'/state.txt';
my $stop_file = abs_path(__FILE__);
$stop_file =~ s/(\.pl|$)/.stop/;
my $help;
my $verbose;
my $filename;
my $url;
my $database;
my $dbhost = 'localhost';
my $user;
my $password;
my $zipped;
my $tile_size = 0.01;
my $clear;
my $bbox_str = '-180,-90,180,90';
my $dbprefix = 'wdi_';
my $user_agent = 'whodidit';
my $hours_to_import_if_no_previous_state = 0;

GetOptions('help' => \$help,
           'v|verbose' => \$verbose,
           'i|input=s' => \$filename,
           'z|gzip' => \$zipped,
           'l|url=s' => \$url,
           'd|database=s' => \$database,
           'h|host=s' => \$dbhost,
           'u|user=s' => \$user,
           'p|password=s' => \$password,
           't|tilesize=f' => \$tile_size,
           'c|clear' => \$clear,
           's|state=s' => \$state_file,
           'w|wget=s' => \$wget,
           'b|bbox=s' => \$bbox_str,
           ) || usage();

usage() if($help);

usage("Please specify database and user names") unless $database && $user;
my $db = DBIx::Simple->connect("DBI:mysql:database=$database;host=$dbhost;mysql_enable_utf8=1", $user, $password, {RaiseError => 1});
$db->query("SET sql_mode = ''");
create_table() if $clear;

if (!$filename && !$url) {
    if ($clear) {
        exit 0;
    } else {
        usage("Please specify either filename or state.txt URL or --clear");
    }
}

my $ua = LWP::UserAgent->new('agent' => $user_agent);
$ua->env_proxy;

my @bbox = split(",", $bbox_str);
die ("badly formed bounding box - use four comma-separated values for left longitude, ".
    "bottom latitude, right longitude, top latitude") unless $#bbox == 3;
die("max longitude is less than min longitude") if ($bbox[2] < $bbox[0]);
die("max latitude is less than min latitude") if ($bbox[3] < $bbox[1]);

if( $filename ) {
    open FH, "<$filename" or die "Cannot open file $filename: $!";
    my $h = $zipped ? new IO::Uncompress::Gunzip(*FH) : *FH;
    print STDERR $filename.': ' if $verbose;
    process_osc($h);
    close $h;
} elsif( $url ) {
    $url =~ s#^#http://# unless $url =~ m#://#;
    $url =~ s#/$##;
    update_state($url);
}

sub update_state {
    my $state_url = shift;
    my $resp = $ua->get($state_url.'/state.txt');
    die "Cannot download $state_url/state.txt: ".$resp->status_line unless $resp->is_success;
    print STDERR "Reading state from $state_url/state.txt\n" if $verbose;
    $resp->content =~ /sequenceNumber=(\d+)/;
    die "No sequence number in downloaded state.txt" unless $1;
    my $last = $1;

    if( !-f $state_file ) {
        # if state file does not exist, create it with the latest state
        open STATE, ">$state_file" or die "Cannot write to $state_file";
        printf STATE "sequenceNumber=%d\n", $last - $hours_to_import_if_no_previous_state;
        close STATE;
    }

    my $cur = $last;
    open STATE, "<$state_file" or die "Cannot open $state_file";
    while(<STATE>) {
        $cur = $1 if /sequenceNumber=(\d+)/;
    }
    close STATE;
    die "No sequence number in file $state_file" if $cur < 0;
    die "Last state $last is less than DB state $cur" if $cur > $last;
    if( $cur == $last ) {
        print STDERR "Current state is the last, no update needed.\n" if $verbose;
        exit 0;
    }

    print STDERR "Last state $cur, updating to state $last\n" if $verbose;
    for my $state ($cur+1..$last) {
        die "$stop_file found, exiting" if -f $stop_file;
        my $osc_url = $state_url.sprintf("/%03d/%03d/%03d.osc.gz", int($state/1000000), int($state/1000)%1000, $state%1000);
        print STDERR $osc_url.': ' if $verbose;
        open FH, "$wget -U$user_agent -q -O- $osc_url|" or die "Failed to open: $!";
        process_osc(new IO::Uncompress::Gunzip(*FH));
        close FH;

        open STATE, ">$state_file" or die "Cannot write to $state_file";
        print STATE "sequenceNumber=$state\n";
        close STATE;
    }
}

sub process_osc {
    my $handle = shift;
    my $r = XML::LibXML::Reader->new(IO => $handle);
    my %comments;
    my %tiles;
    my $state = '';
    my $tilesc = 0;
    my $clock = [gettimeofday];
    while($r->read) {
        if( $r->nodeType == XML_READER_TYPE_ELEMENT ) {
            if( $r->name eq 'modify' ) {
                $state = 'modified';
            } elsif( $r->name eq 'delete' ) {
                $state = 'deleted';
            } elsif( $r->name eq 'create' ) {
                $state = 'created';;
            } elsif( ($r->name eq 'node' || $r->name eq 'way' || $r->name eq 'relation') && $state ) {
                my $changeset = $r->getAttribute('changeset');
                my $change = $comments{$changeset};
                if( !defined($change) ) {
                    $change = get_changeset($changeset);
                    $comments{$changeset} = $change;
                }
                $change->{$r->name.'s_'.$state}++;
                my $time = $r->getAttribute('timestamp');
                $time =~ s/Z\Z//;
                $change->{time} = $time if $time gt $change->{time};

                if( $r->name eq 'node' ) {
                    my $lat = $r->getAttribute('lat');
                    my $lon = $r->getAttribute('lon');
                    next if $lon < $bbox[0] || $lon > $bbox[2] || $lat < $bbox[1] || $lat > $bbox[3];
                    $lat = floor($lat / $tile_size);
                    #$lat = int(89/$tile_size) if $lat >= 90/$tile_size;
                    $lon = floor($lon / $tile_size);
                    #$lon = int(179/$tile_size) if $lon >= 180/$tile_size;

                    my $key = "$lat,$lon,$changeset";
                    my $tile = $tiles{$key};
                    if( !defined($tile) ) {
                        $tile = {
                            lat => $lat,
                            lon => $lon,
                            changeset => $changeset,
                            nodes_created => 0,
                            nodes_modified => 0,
                            nodes_deleted => 0,
                            time => $change->{time}
                        };
                        $tiles{$key} = $tile;
                        $tilesc++;
                    }
                    $tile->{'nodes_'.$state}++;

                    if( $tilesc % 10**5 == 0 ) {
                        flush_tiles(\%tiles, \%comments);
                        %comments = ();
                        %tiles = ();
                    }
                }
            }
        } elsif( $r->nodeType == XML_READER_TYPE_END_ELEMENT ) {
            $state = '' if( $r->name eq 'delete' || $r->name eq 'modify' || $r->name eq 'create' );
        }
    }
    flush_tiles(\%tiles, \%comments) if scalar %tiles;
    printf STDERR ", %d secs\n", tv_interval($clock) if $verbose;
}

sub flush_tiles {my ($tiles, $chs) = @_;
    printf STDERR "[Cnt/Mem: T=%d/%dk C=%d/%dk] ", scalar keys %{$tiles}, total_size($tiles)/1024, scalar keys %{$chs}, total_size($chs)/1024 if $verbose;

    my $sql_ch = <<SQL;
insert into ${dbprefix}changesets
    (changeset_id, change_time, comment, user_id, user_name, created_by,
    nodes_created, nodes_modified, nodes_deleted,
    ways_created, ways_modified, ways_deleted,
    relations_created, relations_modified, relations_deleted)
    values (??)
on duplicate key update
    change_time = values(change_time),
    nodes_created = nodes_created + values(nodes_created),
    nodes_modified = nodes_modified + values(nodes_modified),
    nodes_deleted = nodes_deleted + values(nodes_deleted),
    ways_created = ways_created + values(ways_created),
    ways_modified = ways_modified + values(ways_modified),
    ways_deleted = ways_deleted + values(ways_deleted),
    relations_created = relations_created + values(relations_created),
    relations_modified = relations_modified + values(relations_modified),
    relations_deleted = relations_deleted + values(relations_deleted)
SQL
    my $sql_t = <<SQL;
insert into ${dbprefix}tiles
    (lat, lon, latlon, changeset_id, change_time, nodes_created, nodes_modified, nodes_deleted)
    values (?, ?, ST_SRID(Point(?,?),3857), ?, ?, ?, ?, ?)
on duplicate key update
    nodes_created = nodes_created + values(nodes_created),
    nodes_modified = nodes_modified + values(nodes_modified),
    nodes_deleted = nodes_deleted + values(nodes_deleted)
SQL

    $db->begin;
    eval {
        print STDERR "Writing changesets" if $verbose;
        for my $c (values %{$chs}) {
            $c->{comment} = substr($c->{comment}, 0, 254);
            $c->{comment} = strip_utf8mb4_chars($c->{comment});
            $c->{username} = strip_utf8mb4_chars($c->{username});
            $db->query($sql_ch, $c->{id}, $c->{time}, $c->{comment}, $c->{user_id}, $c->{username}, $c->{created_by},
                $c->{nodes_created}, $c->{nodes_modified}, $c->{nodes_deleted},
                $c->{ways_created}, $c->{ways_modified}, $c->{ways_deleted},
                $c->{relations_created}, $c->{relations_modified}, $c->{relations_deleted}) or die $db->error;
        }

        print STDERR " and tiles" if $verbose;
        for my $t (values %{$tiles}) {
            $db->query($sql_t,
                $t->{lat}, $t->{lon}, $t->{lat}, $t->{lon},
                $t->{changeset}, $t->{time},
                $t->{nodes_created}, $t->{nodes_modified}, $t->{nodes_deleted}) or die $db->error;
        }
        $db->commit or die $db->error;
    };
    if( $@ ) {
        my $err = "Transaction failed: $@";
        eval { $db->rollback; };
        die $err;
    }
    print STDERR " OK" if $verbose;
}

sub strip_utf8mb4_chars() {
    # MySQL "utf8" cannot handle Unicode characters above U+FFFF.
    # https://dev.mysql.com/doc/refman/5.7/en/charset-unicode-conversion.html
    my $str = shift;
    $str =~ s/[\x{10000}-\x{1ffff}]//g;
    return $str;
}

sub get_changeset {
    my $changeset_id = shift;
    return unless $changeset_id =~ /^\d+$/;
    my $resp = $ua->get("https://api.openstreetmap.org/api/0.6/changeset/".$changeset_id);
    die "Failed to read changeset $changeset_id: ".$resp->status_line unless $resp->is_success;
    my $content = $resp->content;
    use Encode;
    $content = Encode::decode_utf8($content);
    my $c = {};
    $c->{id} = $changeset_id;
    $c->{comment} = decode_xml_entities($1) if $content =~ /k=["']comment['"]\s+v="([^"]+)"/;
    $c->{created_by} = decode_xml_entities($1) if $content =~ /k=["']created_by['"]\s+v="([^"]+)"/;
    $content =~ /\suser="([^"]+)"/;
    $c->{username} = decode_xml_entities($1) || '';
    $content =~ /\suid="([^"]+)"/;
    $c->{user_id} = $1 || die("No uid in changeset $changeset_id");
    $c->{nodes_created} = 0; $c->{nodes_modified} = 0; $c->{nodes_deleted} = 0;
    $c->{ways_created} = 0; $c->{ways_modified} = 0; $c->{ways_deleted} = 0;
    $c->{relations_created} = 0; $c->{relations_modified} = 0; $c->{relations_deleted} = 0;
    return $c;
}

sub decode_xml_entities {
    my $xml = shift;
    $xml =~ s/&quot;/"/g;
    $xml =~ s/&apos;/'/g;
    $xml =~ s/&gt;/>/g;
    $xml =~ s/&lt;/</g;
    $xml =~ s/&amp;/&/g;
    return $xml;
}

sub create_table {
    $db->query("drop table if exists ${dbprefix}tiles") or die $db->error;
    $db->query("drop table if exists ${dbprefix}changesets") or die $db->error;

    my $sql = <<SQL;
CREATE TABLE ${dbprefix}tiles (
    lat smallint(6) NOT NULL,
    lon smallint(6) NOT NULL,
    latlon point NOT NULL SRID 3857,
    changeset_id int(10) unsigned NOT NULL,
    change_time datetime NOT NULL,
    nodes_created smallint(5) unsigned NOT NULL,
    nodes_modified smallint(5) unsigned NOT NULL,
    nodes_deleted smallint(5) unsigned NOT NULL,
    PRIMARY KEY (changeset_id,lat,lon),
    SPATIAL KEY idx_latlon (latlon),
    KEY idx_time (change_time)
) ENGINE=MyISAM DEFAULT CHARSET=utf8
SQL
    $db->query($sql) or die $db->error;
    $sql = <<SQL;
CREATE TABLE ${dbprefix}changesets (
    changeset_id int(10) unsigned NOT NULL,
    change_time datetime NOT NULL,
    comment varchar(254) DEFAULT NULL,
    user_id int(10) unsigned NOT NULL,
    user_name varchar(96) NOT NULL,
    created_by varchar(64) DEFAULT NULL,
    nodes_created smallint(5) unsigned NOT NULL,
    nodes_modified smallint(5) unsigned NOT NULL,
    nodes_deleted smallint(5) unsigned NOT NULL,
    ways_created smallint(5) unsigned NOT NULL,
    ways_modified smallint(5) unsigned NOT NULL,
    ways_deleted smallint(5) unsigned NOT NULL,
    relations_created smallint(5) unsigned NOT NULL,
    relations_modified smallint(5) unsigned NOT NULL,
    relations_deleted smallint(5) unsigned NOT NULL,
    PRIMARY KEY (changeset_id),
    KEY idx_user (user_name),
    KEY idx_time (change_time)
) ENGINE=MyISAM DEFAULT CHARSET=utf8
SQL
    $db->query($sql) or die $db->error;
    print STDERR "Database tables were recreated.\n" if $verbose;
}

sub usage {
    my ($msg) = @_;
    print STDERR "$msg\n\n" if defined($msg);

    my $prog = basename($0);
    print STDERR << "TXT";
This script loads into whodidit database contents of a single
osmChange file, or a series of replication diffs. In latter case
it relies on a state.txt file in current directory.

usage: $prog -i osc_file [-z] -d database -u user [-h host] [-p password] [-v]
       $prog -l url           -d database -u user [-h host] [-p password] [-v]

 -i file      : read a single osmChange file.
 -z           : input file is gzip-compressed.
 -l url       : base replication URL, must have a state file.
 -h host      : DB host.
 -d database  : DB database name.
 -u user      : DB user name.
 -p password  : DB password.
 -b bbox      : BBox of a watched region (minlon,minlat,maxlon,maxlat)
 -t tilesize  : size of a DB tile (default=$tile_size).
 -s state     : name of state file (default=$state_file).
 -w wget      : full path to wget tool (default=$wget).
 -c           : drop and recreate DB tables.
 -v           : display messages.

TXT
    exit;
}
