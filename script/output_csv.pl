#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use DBIx::Simple;

# DBHOST:              ec2-54-243-62-232.compute-1.amazonaws.com
# DBNAME:              d92f5ur0t6i0qb
# DBPASS:              EvaMX7gXq9_vQsO5CukWaezj5G
# DBUSER:              qrzrisdtkgbpia

main();

sub main {
    my $forms_id = $ARGV[0];

    my $dbis = DBIx::Simple->new( "dbi:Pg:dbname=d92f5ur0t6i0qb;host=ec2-54-243-62-232.compute-1.amazonaws.com",
                                  "qrzrisdtkgbpia",
                                  "EvaMX7gXq9_vQsO5CukWaezj5G" ) or die DBIx::Simple->error;

    my @products;
    {
        my $rslt = $dbis->query("SELECT * FROM products WHERE is_deleted = FALSE AND id IN ( SELECT products_id FROM form_products WHERE is_deleted = FALSE AND forms_id = ? )", $forms_id)
            or die $dbis->error;
        while( my $line = $rslt->hash ) {
            push( @products, $line );
        }
    }
    my @fields;
    {
        my %options;
        my $opts = $dbis->query("SELECT * FROM field_options WHERE is_deleted = FALSE AND fields_id IN ( SELECT fields_id FROM form_fields WHERE is_deleted = FALSE AND forms_id = ? )", $forms_id )
            or die $dbis->error;
        while( my $line = $opts->hash ) {
            $options{ $line->{fields_id} } = {} unless( exists $options{ $line->{fields_id} } );
            $options{ $line->{fields_id} }->{ $line->{id} } = $line;
        }
        #  SELECT f.* FROM fields AS f, form_fields AS ff WHERE f.id = ff.fields_id AND ff.forms_id = 2 AND ff.is_deleted = FALSE ORDER BY ff.sortorder,ff.id;
        my $rslt = $dbis->query(" SELECT f.* FROM fields AS f, form_fields AS ff WHERE f.id = ff.fields_id AND ff.forms_id = ? AND ff.is_deleted = FALSE ORDER BY ff.sortorder,ff.id;", $forms_id )
            or die $dbis->error;
        while( my $line = $rslt->hash ) {
            $line->{options} = $options{ $line->{id} };
            push( @fields, $line );
        }
    }
    my %applicants_data;
    {
        my $rslt = $dbis->query( "SELECT * FROM applicant_data WHERE is_deleted = FALSE AND applicant_form_id IN ( SELECT id FROM applicant_form WHERE is_deleted = FALSE AND forms_id = ? );",
                                 $forms_id )
            or die $dbis->error;
        while( my $line = $rslt->hash ) {
            $applicants_data{ $line->{applicants_id} } = {} unless( exists $applicants_data{ $line->{applicants_id} } );
            $applicants_data{ $line->{applicants_id} }->{ $line->{fields_id} } = $line;
        }
    }
    my %applicants_products;
    {
        my $rslt = $dbis->query( "SELECT * FROM applicant_form_products WHERE is_deleted = FALSE AND applicant_form_id IN ( SELECT id FROM applicant_form WHERE is_deleted = FALSE AND forms_id = ? );",
                                 $forms_id )
            or die $dbis->error;
        while( my $line = $rslt->hash ) {
            $applicants_products{ $line->{applicants_id} } = {} unless( exists $applicants_products{ $line->{applicants_id} } );
            $applicants_products{ $line->{applicants_id} }->{ $line->{products_id} } = $line;
        }
    }
    # SELECT a.id, a.email, af.date_created FROM applicants AS a, applicant_form AS af WHERE a.is_deleted = FALSE AND af.is_deleted = FALSE AND af.applicants_id = a.id ORDER BY af.date_created;
    my $rslt = $dbis->query( "SELECT a.id, a.email, af.date_created FROM applicants AS a, applicant_form AS af WHERE af.forms_id = ? AND a.is_deleted = FALSE AND af.is_deleted = FALSE AND af.applicants_id = a.id ORDER BY af.date_created;", $forms_id )
        or die $dbis->error;
    printf('"email","date_created"');
    foreach my $f ( @fields ) {
        printf(',"%s"', $f->{name});
    }
    foreach my $p ( @products ) {
        printf(',"%s"', $p->{name} );
    }
    print "\n";
    while( my $line = $rslt->hash ) {
        printf('"%s","%s"', $line->{email} || '', $line->{date_created} || '' );
        foreach my $f ( @fields ) {
            printf(',"%s"', ( exists $applicants_data{ $line->{id} } and exists $applicants_data{ $line->{id} }->{ $f->{id} } )
                            ? ( $f->{type} =~ /^text/ ? $applicants_data{ $line->{id} }->{ $f->{id} }->{text}
                                                      : $f->{options}->{ $applicants_data{ $line->{id} }->{ $f->{id} }->{field_options_id} }->{name} )
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
