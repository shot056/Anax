package Anax::Admin::Fields;

use strict;
use warnings;

use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';
#use Mojo::ByteStream 'b';

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

my $vc = Validator::Custom::Anax->new;

sub index {
    my $self = shift;
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $rslt = $dbis->select('fields', ['*'], { is_deleted => 0, is_global => 1 }, { order_by => 'id' } )
        or die $dbis->error;
    $self->stash( datas => $rslt );
    $self->render();
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

sub input {
    my $self = shift;
    my $params = $self->req->params->to_hash;
    if( my $id = $self->stash('id') ) {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        my $rslt = $dbis->select('fields', ['*'], { id => $id, is_deleted => 0 } )
            or die $dbis->error;
        $self->render_not_found unless( $rslt->rows );
        $params = $rslt->hash;
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
    }
    $self->stash( messages => {}, params => $params );
    $self->render();
}

sub register {
    my $self = shift;
    my $id   = $self->stash('id');
    
    my $params = $self->req->params->to_hash;
    $self->app->log->info( "params : " . Dumper( $params ) );
    my $rule = [
                name => [ [ 'not_blank', '必ず入力してください' ],
                        ],
#                type => [ [ 'not_blank', '必ず選択してください' ],
#                          [ [ qw/textfield checkbox radio textarea/ ], '必ず選択してください' ]
#                        ],
               ];
    if( exists $params->{forms_id} ) {
        push( @{ $rule }, ( forms_id => [ [ 'int', 'what is up ?' ] ] ) );
    }
    my $vrslt = $vc->validate( $params, $rule );
    $self->app->log->debug( Dumper( { vrslt => $vrslt, is_ok => $vrslt->is_ok } ) );
    unless( $vrslt->is_ok ) {
        $self->stash( missing => 1 ) if( $vrslt->has_missing );
        $self->stash( messages => $vrslt->messages_to_hash )
            if( $vrslt->has_invalid );
        $self->app->log->debug( Dumper( $self->stash ) );
        $self->render( template => 'admin/fields/input', params => $params );
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        my $hash = { name => $params->{name} || '',
                     type => $params->{type} || '',
                     default => $params->{default} || '',
                     is_global => $params->{is_global} ? 1 : 0,
                     is_required => $params->{is_required} ? 1 : 0
                   };
        if( defined $id and $id =~ /^\d+$/ ) {
            $hash->{date_updated} = 'now';
            $dbis->update( 'fields', $hash, { id => $id } )
                or die $dbis->error;
        }
        else {
            $dbis->insert( 'fields', $hash )
                or die $dbis->error;
            if( exists $params->{forms_id} and $params->{forms_id} =~ /^\d+$/ ) {
                my $fields_id = $dbis->last_insert_id( undef, 'public', 'fields', 'id' ) or die $dbis->error;
                $dbis->insert( 'form_fields', { forms_id => $params->{forms_id}, fields_id => $fields_id } )
                    or die $dbis->error;
            }
        }
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( ( $params->{forms_id} ? 'admin/forms/view/' . $params->{forms_id} :  'admin/fields' ) );
    }
}

sub view {
    my $self = shift;
    my $id   = $self->stash('id');

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $it = $dbis->select( 'fields', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    $self->render_not_found unless( $it->rows );
    my $data = $it->hash;

    if( grep( $_ eq $data->{type}, qw/checkbox radio popup select/ ) ) {
        my $options_it = $dbis->select( 'field_options', ['*'], { is_deleted => 0, fields_id => $data->{id} } )
            or die $dbis->error;
        $self->stash( options => $options_it );
    }
    else {
        $self->stash( options => {} );
    }
    $self->render( template => 'admin/fields/view', hash => $data );
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}

sub disable {
    my $self = shift;
    my $id   = $self->stash('id');

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $it = $dbis->select( 'fields', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    $self->render_not_found unless( $it->rows );
    my $data = $it->hash;

    if( grep( $_ eq $data->{type}, qw/checkbox radio popup select/ ) ) {
        my $options_it = $dbis->select( 'field_options', ['*'], { is_deleted => 0, fields_id => $data->{id} } )
            or die $dbis->error;
        $self->stash( options => $options_it );
    }
    else {
        $self->stash( options => {} );
    }
    $self->stash( hash => $data );
    $self->render( template => 'admin/fields/disable' );
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}

sub do_disable {
    my $self = shift;
    my $id   = $self->stash('id');
    
    my $params = $self->req->params->to_hash;
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    
    $dbis->update( 'fields', { is_deleted => 1, date_deleted => 'now' }, { id => $id } )
        or die $dbis->error;
    $dbis->update( 'field_options', { is_deleted => 1, date_deleted => 'now' }, { fields_id => $id } )
        or die $dbis->error;
    
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( ( $params->{forms_id} ? 'admin/forms/view/' . $params->{forms_id} :  'admin/fields' ) );
}

1;