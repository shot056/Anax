#!/bin/env perl

use strict;
use warnings;

use DBIx::Simple;

sub do_update_2013011001 {
    my $dbis = shift;

    exec_sql( $dbis, "INSERT INTO fields ( is_global, name, type, is_required, error_check, sortorder ) VALUES( TRUE, 'email', 'textfield', TRUE, 'email', 0 );" );
    my $fields_id = $dbis->last_insert_id( undef, 'public', 'fields', 'id' );
    
    my $forms_it = exec_sql( $dbis, "SELECT id FROM forms ORDER BY id" );
    while( my $forms = $forms_it->hash ) {
        exec_sql( $dbis, "INSERT INTO form_fields ( forms_id, fields_id, sortorder ) VALUES( ?, ?, 0 );", $forms->{id}, $fields_id );
    }
    my $now_email = exec_sql( $dbis, "SELECT a.id AS a_id, a.email, af.id AS af_id, af.forms_id FROM applicants AS a, applicant_form AS af WHERE a.id = af.applicants_id ORDER BY a_id, af_id;" );
    while( my $line = $now_email->hash ) {
        exec_sql( $dbis, "INSERT INTO applicant_data ( applicant_form_id, applicants_id, forms_id, fields_id, text ) VALUES( ?, ?, ?, ?, ? );",
                  $line->{af_id}, $line->{a_id}, $line->{forms_id}, $fields_id, $line->{email} );
    }
    exec_sql( $dbis, "ALTER TABLE applicants ALTER COLUMN email DROP NOT NULL" );
    
    return "1";
}


1;
