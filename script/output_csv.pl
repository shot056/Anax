#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use DBIx::Simple;
use Encode qw/encode/;

# DBHOST:              ec2-54-243-62-232.compute-1.amazonaws.com
# DBNAME:              d92f5ur0t6i0qb
# DBPASS:              EvaMX7gXq9_vQsO5CukWaezj5G
# DBUSER:              qrzrisdtkgbpia

main();

sub exec_sql {
    my $dbis = shift;
    my $sql  = shift;
    my @bind = shift;

#    print STDERR "$sql; (" . join(",", @bind) . ")\n";
    return $dbis->query( $sql, @bind )
        or die $dbis->error;
}

sub main {
    my $forms_id = $ARGV[0];

    my $dbis = DBIx::Simple->new( "dbi:Pg:dbname=$ENV{DBNAME};host=$ENV{DBHOST}",
                                  "$ENV{DBUSER}",
                                  "$ENV{DBPASS}" ) or die DBIx::Simple->error;

    my @products;
    {
        my $rslt = exec_sql( $dbis, "SELECT * FROM products WHERE is_deleted = FALSE AND id IN ( SELECT products_id FROM form_products WHERE forms_id = ? ) ORDER BY id", $forms_id );
        while( my $line = $rslt->hash ) {
            push( @products, $line );
        }
    }
    my @fields;
    {
        my %options;
        my $opts = exec_sql( $dbis, "SELECT * FROM field_options WHERE is_deleted = FALSE AND fields_id IN ( SELECT fields_id FROM form_fields WHERE forms_id = ? ) ORDER BY id", $forms_id );
        while( my $line = $opts->hash ) {
            $options{ $line->{fields_id} } = {} unless( exists $options{ $line->{fields_id} } );
            $options{ $line->{fields_id} }->{ $line->{id} } = $line;
        }
        #  SELECT f.* FROM fields AS f, form_fields AS ff WHERE f.id = ff.fields_id AND ff.forms_id = 2 AND ff.is_deleted = FALSE ORDER BY ff.sortorder,ff.id;
        my $rslt = exec_sql( $dbis, " SELECT f.* FROM fields AS f, form_fields AS ff WHERE f.id = ff.fields_id AND ff.forms_id = ? AND ff.is_deleted = FALSE ORDER BY ff.sortorder,ff.id;", $forms_id );
        while( my $line = $rslt->hash ) {
            $line->{options} = $options{ $line->{id} };
            push( @fields, $line );
        }
    }
    my %applicants_data;
    {
        my $rslt = exec_sql( $dbis, "SELECT * FROM applicant_data WHERE is_deleted = FALSE AND applicant_form_id IN ( SELECT id FROM applicant_form WHERE is_deleted = FALSE AND forms_id = ? );",
                             $forms_id );
        while( my $line = $rslt->hash ) {
            $applicants_data{ $line->{applicants_id} } = {} unless( exists $applicants_data{ $line->{applicants_id} } );
            $applicants_data{ $line->{applicants_id} }->{ $line->{fields_id} } = $line;
        }
    }
    my %applicants_products;
    {
        my $rslt = exec_sql( $dbis, "SELECT * FROM applicant_form_products WHERE is_deleted = FALSE AND applicant_form_id IN ( SELECT id FROM applicant_form WHERE is_deleted = FALSE AND forms_id = ? );",
                             $forms_id );
        while( my $line = $rslt->hash ) {
            $applicants_products{ $line->{applicants_id} } = {} unless( exists $applicants_products{ $line->{applicants_id} } );
            $applicants_products{ $line->{applicants_id} }->{ $line->{products_id} } = $line;
        }
    }
    # SELECT a.id, a.email, af.date_created FROM applicants AS a, applicant_form AS af WHERE a.is_deleted = FALSE AND af.is_deleted = FALSE AND af.applicants_id = a.id ORDER BY af.date_created;
    my $rslt = exec_sql( $dbis, "SELECT a.id, a.email, af.date_created FROM applicants AS a, applicant_form AS af WHERE af.forms_id = ? AND a.is_deleted = FALSE AND af.is_deleted = FALSE AND af.applicants_id = a.id ORDER BY af.date_created;", $forms_id );
    printf('"id","email","date_created"');
    foreach my $f ( @fields ) {
        printf(',"%s"', encode( 'utf-8', $f->{name} ) );
    }
    foreach my $p ( @products ) {
        printf(',"%s"', encode( 'utf-8', $p->{name} ) );
    }
    print "\n";
    while( my $line = $rslt->hash ) {
        printf('%d,"%s","%s"', $line->{id}, $line->{email} || '', $line->{date_created} || '' );
        foreach my $f ( @fields ) {
            printf(',"%s"', ( exists $applicants_data{ $line->{id} } and exists $applicants_data{ $line->{id} }->{ $f->{id} } )
                            ? ( ( $f->{type} =~ /^text/ ? ( encode( 'utf-8', $applicants_data{ $line->{id} }->{ $f->{id} }->{text} ) || '' )
                                                      : encode( 'utf-8', $f->{options}->{ $applicants_data{ $line->{id} }->{ $f->{id} }->{field_options_id} }->{name} ) || undef ) )
                            : '' );
        }
        foreach my $p ( @products ) {
            printf(',%s', ( exists $applicants_products{ $line->{id} } and $applicants_products{ $line->{id} }->{ $p->{id} } )
                            ? sprintf('%d', $applicants_products{ $line->{id} }->{ $p->{id} }->{number} )
                            : '' );
        }
        print "\n";
    }
}
