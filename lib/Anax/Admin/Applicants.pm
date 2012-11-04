package Anax::Admin::Applicants;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';


use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

sub index {
    my $self = shift;
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $rslt = $dbis->query( "SELECT a.id, a.email, a.date_created, a.date_updated, f.id AS form_id, f.name AS form_name, af.date_created AS af_date_created, af.date_updated AS af_date_updated  FROM applicants AS a, forms AS f, applicant_form AS af WHERE a.is_deleted = FALSE AND a.id=af.applicants_id AND f.id=af.forms_id;" )
        or die $dbis->error;
    $self->render( template => 'admin/applicants/index', datas => $rslt );
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}


1;
