package Anax::Admin::Field::Options;

use strict;
use warnings;

use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';
#use Mojo::ByteStream 'b';

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;


my $vc = Validator::Custom::Anax->new;


sub input {
    my $self     = shift;
    my $field_id = $self->stash('field_id');

    $self->stash( messages => {} );
    $self->render;
}

sub register {
    my $self     = shift;
    my $field_id = $self->stash('field_id');

    my $params = $self->req->params->to_hash;
    
#    $self->app->log->debug( Dumper( $params ) );

    $params->{options} =~ s/\r\n/\n/g;
    my @options = split/\n/, $params->{options};

    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    for( my $i = 0; $i < scalar @options; $i ++ ) {
        $dbis->insert( 'field_options', { fields_id => $field_id,
                                          sortorder => $i + 1,
                                          name      => $self->encode( $options[ $i ] ) } )
            or die $dbis->error;
    }
    
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( $self->get_path( '/admin/fields/view/' . $field_id . ( $params->{forms_id} ? '?forms_id=' . $params->{forms_id} : '' ) ) );
}


1;
