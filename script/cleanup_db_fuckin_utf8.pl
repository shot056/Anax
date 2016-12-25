#!/bin/env perl

use strict;
use warnings;

use FindBin;

use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
my $mode = 'development';

use DBIx::Simple;
use Data::Dumper;
use Data::Visitor::Callback;
use Mojo::ByteStream;

sub dumper {
    return Data::Dumper->new( \@_ )->Sortkeys( 1 )->Dump;
}

sub decode {
    my $str  = shift;
    return '' unless( defined $str and length( $str ) );
    my $undef = undef;
    my $ret = Mojo::ByteStream->new( $str )->decode->to_string;
    return ( ( defined $ret and length( $ret ) ) ? $ret : $str );
}
sub encode {
    my $str  = shift;
                       return '' unless( defined $str and length( $str ) );
    my $undef = undef;
    my $ret = Mojo::ByteStream->new( $str )->encode->to_string;
    return ( ( defined $ret and length( $ret ) ) ? $ret : $str );
}
my $v_decode = Data::Visitor::Callback->new(
                                            scalar => sub {},
                                            plain_value => sub {
                                                my $self = shift;
                                                my $str = shift;
                                                my $ret = decode( $str );
                                                return "$ret";
                                            }
                                           );
sub vd {
    my $data = shift;
    return $v_decode->visit( $data );
}
my $v_encode = Data::Visitor::Callback->new(
                                            scalar => sub {},
                                            plain_value => sub {
                                                my $self = shift;
                                                my $str = shift;
                                                my $ret = encode( $str );
                                                return "$ret";
                                            }
                                           );
sub ve {
    my $data = shift;
    return $v_encode->visit( $data );
}

my $v_v = Data::Visitor::Callback->new(
                                       scalar => sub {},
                                       plain_value => sub {
                                                       my $self = shift;
                                                       my $str = shift;
                                                       return "$str";
                                                      }
                                      );
sub vv {
    my $data = shift;
    return $v_v->visit( $data );
}

GetOptions( 'mode|m=s' => \$mode );

main();


sub main {
    my $dbis_utf8    = DBIx::Simple->new( @{ get_dsn(1) } ) or die DBIx::Simple->error;
    my $dbis_nonutf8 = DBIx::Simple->new( @{ get_dsn(0) } ) or die DBIx::Simple->error;

    $dbis_nonutf8->begin_work or die $dbis_nonutf8->error;

    my $tables_it = $dbis_nonutf8->select('pg_catalog.pg_tables', [ '*' ], { schemaname => 'public', 'tablename' => { '!=' => 'system_settings' } }, { -asc => 'tablename' } )
        or die $dbis_nonutf8->error; # select * from pg_catalog.pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    while( my $table = $tables_it->hash ) {
        print "-" x 100, "\n";
        print "TABLE $table->{tablename} ...";
        my $it = $dbis_utf8->select( $table->{tablename}, [ '*' ], {}, { -asc => 'id' } )
            or die $dbis_utf8->error;
        my $all = $it->rows;
        my $count = 0;
        while( my $line = $it->hash ) {
            $count ++;
            print "\rTABLE $table->{tablename} ... $count/$all          ";
#            print dumper( $line );
            my $hash = {};
            foreach my $key ( keys( %{ $line } ) ) {
                next unless( $line->{$key} );
                next if( $line->{$key} =~ /^[a-zA-Z0-9 \+\.:-]+$/ );
                my $newkey = $key;
                $newkey = "\"$key\"" if( grep( $key eq $_, qw/default from to/ ) );
                $hash->{$newkey} = $line->{$key};
            }
#            print dumper( { org => $hash, vvvevd => vv( ve( vd( $hash ) ) ) } );
            if( scalar keys( %{ $hash } ) > 0 ) {
                $dbis_nonutf8->update( $table->{tablename}, vd( vv( ve( vd( $hash ) ) ) ), { id => $line->{id} } )
                    or die $dbis_nonutf8->error;
            }
        }
#        print "\rTABLE $table->{tablename} ... complete";
        print "\n";
        
        # my $ait = $dbis_nonutf8->select( $table->{tablename}, [ '*' ] )
        #     or die $dbis_nonutf8->error;
        # while( my $line = $ait->hash ) {
        #     print dumper( $line );
        # }
    }
    print "=" x 100, "\n";
    if( yn( "realy commit ?" ) ) {
        print "    COMMIT !\n";
        $dbis_nonutf8->commit;
    } else {
        print "    abort !\n";
        $dbis_nonutf8->rollback;
    }
}

sub yn {
    my $msg = shift;
    
    print "$msg [y/N] ";
    my $yn = <STDIN>;
    if( lc( $yn ) =~ /^y/ ) {
        return 1;
    } else {
        return 0;
    }
}
sub get_dsn {
    my $utf8 = shift;
    
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
    $config->{dsn}->[3]->{pg_enable_utf8} = $utf8;
    print dumper( $config->{dsn} );
    return $config->{dsn};
}
