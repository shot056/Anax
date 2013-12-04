#!/bin/env perl

use strict;
use warnings;

BEGIN {
    use FindBin;
    $ENV{MOJO_HOME} = "$FindBin::Bin/../";
};
use lib ( "$FindBin::Bin/../lib/",
          "$FindBin::Bin/../local/lib/perl5/",
          "$FindBin::Bin/../local/lib/perl5/x86_64-linux/" );

use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);

use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use FindBin;
use DBIx::Simple;
use File::Find::Iterator;

use Data::Dumper;

my $mode = 'development';
my $host;
my $port;
my $name;
my $user;
my $pass;
my $help = 0;
my $debug = 0;

GetOptions( 'mode|m=s' => \$mode,
            'host|H=s' => \$host,
            'port|p=s' => \$port,
            'name|n=s' => \$name,
            'user|u=s' => \$user,
            'pass|w=s' => \$pass,
            'debug|d'  => \$debug,
            'help|h'   => \$help );

main();


sub main {
    if( $help ) {
        print join( "\n",
                    "Database Update Script",
                    "--------------------------------------------------",
                    "Usage: $0 --mode=MODE --host=DBHOST --port=DBPORT --name=DBNAME --user=USER --pass=PASSWORD --debug --help",
                    " -- options -- ",
                    "     : mode|m  : running mode for load conf/XXXX.pl",
                    "     : host|H  : database host",
                    "     : port|p  : database port",
                    "     : name|n  : database name",
                    "     : user|u  : database user",
                    "     : pass|w  : database password",
                    "     : debug|d : printout exec sql",
                    "     : help|h  : show this message",
                    "" );
        exit( -1 );
    }
    my $dsn = get_dsn();
    error_exit( "DSN is not defined" )
        unless( defined $dsn and ref( $dsn ) eq 'ARRAY' and scalar @{$dsn} );
    print RED "Connect to $dsn->[0]\n";
    my $dbis = DBIx::Simple->new( @{$dsn} )
        or die "can not connect to $dsn->[0] : " . DBIx::Simple->error;
    $dbis->begin_work or die $dbis->error;

    check_system_setting_table( $dbis );
    my $now_version_date = get_now_version( $dbis );
    print "now sql version is '", GREEN, $now_version_date, WHITE, "'\n";
    my $now = $now_version_date;
    $now =~ s/-//g;
    my $home = "$FindBin::Bin/../";
    my $find = File::Find::Iterator->create( dir => [ "${home}sql/update" ],
                                             filter => sub { -f and m/\.(sql|pl)$/ } );
    my @files;
    while( my $file = $find->next ) {
        push( @files, $file );
    }
    my $do_flg = 0;
    foreach my $file ( sort @files ) {
        my ($version_date, $ext) = $file =~ m!(\d{4}-\d{2}-\d{2}-\d+)\.(sql|pl)$!;
        my $version = $version_date;
        $version =~ s/-//g;
        my $relpath = $file;
        $relpath =~ s/^$home//;
        
        if( $now < $version ) {
            $do_flg = 1;
            print YELLOW "do update : ", BLUE, $relpath, WHITE, "\n";
            my $rslt;
            if( $ext eq 'sql' ) {
                $rslt = do_update_sql( $dbis, $file );
            }
            elsif( $ext eq 'pl' ) {
                $rslt = do_update_pl( $dbis, $file, $version );
            }
            die RED BOLD "update failure : rollback" unless( $rslt );
            exec_sql( $dbis, "UPDATE system_settings SET data = ? WHERE name = 'sql_version'", $version_date );
        }
    }
    unless( $do_flg ) {
        print YELLOW "update target is not found\n";
    }
    else {
        print GREEN "all update is completed: commit\n";
        $dbis->commit or die $dbis->error;
    }
    
    exit( 0 );
}

sub exec_sql {
    my $dbis = shift;
    my $sql  = shift;
    my @vals = @_;

    $sql .= ';' unless( $sql =~ /;$/ );
    if( $debug ) {
        print CYAN "exec sql : \n", WHITE "$sql";
        print " ( '".join("', '",@vals)."' )" if( scalar @vals );
        print "\n";
    }
    return $dbis->query( $sql, @vals ) or die $dbis->error;
}

sub do_update_sql {
    my $dbis = shift;
    my $file = shift;

    open( SQL, $file ) or die "can not open $file : $!";
    my $sqlbuf = "";
    
    while( my $line = <SQL> ) {
        chomp( $line );
        $line =~ s/\s+$//;
        next if( $line =~ /^--/ or length( $line ) < 1 );
        $sqlbuf .= "$line\n";
        if( $sqlbuf =~ /;$/ ) {
            exec_sql( $dbis, $sqlbuf );
            $sqlbuf = "";
        }
    }
    close( SQL );
    if( length( $sqlbuf ) ) {
        exec_sql( $dbis, $sqlbuf );
    }
    return 1;
}

sub do_update_pl {
    my $dbis = shift;
    my $file = shift;
    my $version = shift;

    my $ret = eval {
        require "$file";
        my $method = "do_update_$version";
        {
            no strict;
            my $return = &$method( $dbis );
            use strict;
            return $return;
        }
    };
    if( $@ ) {
        print "$@";
        return 0;
    }
}

sub get_now_version {
    my $dbis = shift;
    my $rslt = exec_sql( $dbis, "SELECT data FROM system_settings WHERE is_deleted = FALSE AND name = 'sql_version'" );
    die RED BOLD "sql_version data is not found."
        unless( $rslt->rows );
    my $version = $rslt->hash->{data};
    return $version;
}

sub check_system_setting_table {
    my $dbis = shift;
    my $rslt = exec_sql( $dbis, "SELECT * FROM pg_catalog.pg_tables WHERE schemaname = 'public' AND tablename = 'system_settings';" );
    my $flg = $rslt->rows;
    unless( $flg ) {
        print RED "system_settings table is not exists.\n";
        print GREEN "creating table...\n";
        my $sql = join("",<DATA>);
        exec_sql( $dbis, $sql );
        exec_sql( $dbis, "INSERT INTO system_settings ( name, data ) VALUES( 'sql_version', '1970-01-01-01' )" );
    }
}

sub get_dsn {
    my $dsn;
    if( defined $name and length( $name ) ) {
        $host = "localhost" unless( defined $host );
        $user = $ENV{USER} unless( defined $user );
        $dsn = [ "dbi:Pg:dbname=$name",
                 $user,
                 $pass || "",
                 { AutoCommit => 1, RaiseError => 1 } ];
        $dsn->[0] = "$dsn->[0];host=$host" if( defined $host and length( $host ) );
        $dsn->[0] = "$dsn->[0];port=$port" if( defined $port and length( $port ) );
    }
    else {
        my $config = {};;
        if( -f "$FindBin::Bin/../anax.conf" ) {
            $config = do( "$FindBin::Bin/../anax.conf" );
            die "$@" if( $@ );
        }
        if( -f "$FindBin::Bin/../anax.$mode.conf" ) {
            my $tmpconfig = do( "$FindBin::Bin/../anax.$mode.conf" );
            die "$@" if( $@ );
            $config = { %{$config}, %{$tmpconfig} };
        }
        if( exists $config->{dsn} and ref( $config->{dsn} ) eq 'ARRAY' ) {
            $dsn = $config->{dsn}
        }
    }
    return $dsn;
}
sub error_exit {
    my $msg = shift;
    print "$msg\n";
    exit( -1 );
}


__DATA__
CREATE TABLE system_settings (
  "name" varchar(32) NOT NULL PRIMARY KEY,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  date_created timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_updated timestamp NULL DEFAULT NULL,
  date_deleted timestamp NULL DEFAULT NULL,
  "data" varchar(128) NOT NULL
);
CREATE INDEX idx_system_settings_name ON system_settings ( name );
CREATE INDEX idx_system_settings_is_deleted ON system_settings ( is_deleted );

