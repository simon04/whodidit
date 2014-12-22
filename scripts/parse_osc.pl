#!/usr/bin/perl

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

GetOptions(#'h|help' => \$help,
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

if( $help ) {
  usage();
}

usage("Please specify database and user names") unless $database && $user;
my $db = DBIx::Simple->connect("DBI:mysql:database=$database;host=$dbhost;mysql_enable_utf8=1", $user, $password, {RaiseError => 1});
create_table() if $clear;
my $ua = LWP::UserAgent->new();
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
} else {
    usage("Please specify either filename or state.txt URL");
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
        print STATE "sequenceNumber=$last\n";
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
        open FH, "$wget -q -O- $osc_url|" or die "Failed to open: $!";
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
                $state = 'created';
            } elsif( ($r->name eq 'node' || $r->name eq 'way' || $r->name eq 'relation') && $state ) {
                my $changeset = $r->getAttribute('changeset');
                my $change = $comments{$changeset};
                if( !defined($change) ) {
                    $change = get_changeset($changeset);
                    $comments{$changeset} = $change;
                }
                $change->{$r->name.'s_'.$state}++;
                my $time = $r->getAttribute('timestamp');
                $change->{time} = $time if $time gt $change->{time};

                if( $r->name eq 'node' ) {
                    my $lat = $r->getAttribute('lat');
                    my $lon = $r->getAttribute('lon');
                    next if $lon < $bbox[0] || $lon > $bbox[2] || $lat < $bbox[1] || $lat > $bbox[2];
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
    fill_changesets(\%{$chs});
    printf STDERR "[Cnt/Mem: T=%d/%dk C=%d/%dk] ", scalar keys %{$tiles}, total_size($tiles)/1024, scalar keys %{$chs}, total_size($chs)/1024 if $verbose;

    my $sql_ch = <<CHSQL;
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
CHSQL
    my $sql_t = <<CHSQL;
insert into ${dbprefix}tiles
    (lat, lon, latlon, changeset_id, change_time, nodes_created, nodes_modified, nodes_deleted)
    values (?, ?, Point(?,?), ?, ?, ?, ?, ?)
on duplicate key update
    nodes_created = nodes_created + values(nodes_created),
    nodes_modified = nodes_modified + values(nodes_modified),
    nodes_deleted = nodes_deleted + values(nodes_deleted)
CHSQL

    $db->begin;
    eval {
        print STDERR "Writing changesets" if $verbose;
        for my $c (values %{$chs}) {
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
        $db->commit;
    };
    if( $@ ) {
        eval { $db->rollback; };
        die "Transaction failed: $@";
    }
    print STDERR " OK" if $verbose;
}

sub get_changeset {
    my $changeset_id = shift;
    return unless $changeset_id =~ /^\d+$/;
    my $c = {};
    $c->{id} = $changeset_id;
    $c->{nodes_created} = 0; $c->{nodes_modified} = 0; $c->{nodes_deleted} = 0;
    $c->{ways_created} = 0; $c->{ways_modified} = 0; $c->{ways_deleted} = 0;
    $c->{relations_created} = 0; $c->{relations_modified} = 0; $c->{relations_deleted} = 0;
    return $c;
}

sub fill_changesets {
    my ($comments) = @_;
    my @changeset_ids = keys %{$comments};
    my @chunks;
    push @chunks, [ splice @changeset_ids, 0, 100 ] while @changeset_ids;
    foreach (@chunks) {
        @changeset_ids = @{$_};
        my $changesets_url = "http://api.openstreetmap.org/api/0.6/changesets/?changesets=".join(',',@changeset_ids);
        open(my $FILE, "$wget -q -O- $changesets_url|") or die "Failed to open: $!";
        my $r = XML::LibXML::Reader->new(IO => $FILE);
        my $changeset_id;
        while($r->read) {
            if( $r->nodeType == XML_READER_TYPE_ELEMENT ) {
                if( $r->name eq 'changeset' ) {
                    $changeset_id = $r->getAttribute('id');
                    $comments->{$changeset_id}->{username} = decode_xml_entities($r->getAttribute('user'));
                    $comments->{$changeset_id}->{user_id}  = decode_xml_entities($r->getAttribute('uid'));
                } elsif( $r->name eq 'tag' ) {
                    my $k = $r->getAttribute('k');
                    my $v = $r->getAttribute('v');
                    if ($k eq "comment") {
                        $comments->{$changeset_id}->{comment} = decode_xml_entities($v);
                    }
                    if ($k eq "created_by") {
                        $comments->{$changeset_id}->{created_by} = decode_xml_entities($v);
                    }
                }
            }
        }
        close($FILE);
    }
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

    my $sql = <<CREAT1;
CREATE TABLE ${dbprefix}tiles (
    lat smallint(6) NOT NULL,
    lon smallint(6) NOT NULL,
    latlon point NOT NULL,
    changeset_id int(10) unsigned NOT NULL,
    change_time datetime NOT NULL,
    nodes_created smallint(5) unsigned NOT NULL,
    nodes_modified smallint(5) unsigned NOT NULL,
    nodes_deleted smallint(5) unsigned NOT NULL,
    PRIMARY KEY (changeset_id,lat,lon),
    SPATIAL KEY idx_latlon (latlon),
    KEY idx_time (change_time)
) ENGINE=MyISAM DEFAULT CHARSET=utf8
CREAT1
    $db->query($sql) or die $db->error;
    $sql = <<CREAT2;
CREATE TABLE ${dbprefix}changesets (
    changeset_id int(10) unsigned NOT NULL,
    change_time datetime NOT NULL,
    comment varchar(254) DEFAULT NULL,
    user_id mediumint(8) unsigned NOT NULL,
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
CREAT2
    $db->query($sql) or die $db->error;
    print STDERR "Database tables were recreated.\n" if $verbose;
}

sub usage {
    my ($msg) = @_;
    print STDERR "$msg\n\n" if defined($msg);

    my $prog = basename($0);
    print STDERR << "EOF";
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

EOF
    exit;
}
