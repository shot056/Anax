package Anax::Admin::Forms;

use strict;
use warnings;
use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::ByteStream 'b';

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

my $vc = Validator::Custom::Anax->new;

sub index {
    my $self = shift;
    $self->app->log->debug( Dumper( $self->app->config ) );
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $rslt = $dbis->select( 'forms', ['*'], { is_deleted => 0 } )
        or die $dbis->error;
    $self->render( template => 'admin/forms/index', datas => $rslt );
    $dbis->commit;
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
        my $rslt = $dbis->select('forms', ['*'], { id => $id, is_deleted => 0 } )
            or die $dbis->error;
        $self->render_not_found unless( $rslt->rows );
        $params = $rslt->hash;
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
    }
    $self->stash(  messages => {}, params => $params );
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
                key  => [ [ 'not_blank', '必ず入力してください' ],
                          [ { length => [ 3, 8 ] }, '3文字以上、8文字以下で入力してください' ],
                          [ 'ascii', '半角英数字で入力してください' ]
                        ],
               ];
    my $vrslt = $vc->validate( $params, $rule );
    $self->app->log->debug( Dumper( { vrslt => $vrslt, is_ok => $vrslt->is_ok } ) );
    unless( $vrslt->is_ok ) {
        $self->stash( missing => 1 ) if( $vrslt->has_missing );
        $self->stash( messages => $vrslt->messages_to_hash )
            if( $vrslt->has_invalid );
        $self->app->log->debug( Dumper( $self->stash ) );
        $self->render( template => 'admin/forms/input', params => $params );
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        my $hash = { key => $params->{key},
                     name => $params->{name},
#                     is_published => $params->{is_published}
                   };
        if( defined $id and $id =~ /^\d+$/ ) {
            $hash->{date_updated} = 'now';
            $dbis->update( 'forms', $hash, { id => $id } )
                or die $dbis->error;
        }
        else {
            $dbis->insert( 'forms', $hash )
                or die $dbis->error;
        }
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( '/admin/forms' );
    }
}

sub view {
    my $self = shift;
    my $id   = $self->stash('id');
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    my $it = $dbis->select( 'forms', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    $self->render_not_found unless( $it->rows );
    my $data = $it->hash;
#    my $fields_it = $dbis->select( 'form_fields', ['*'],
#                                   { is_deleted => 0, forms_id => $data->{id} },
#                                   { order_by => 'sortorder, id' } )
#        or die $dbis->error;
    my $fields_it = $dbis->query( "SELECT f.*, ff.sortorder AS p_sortorder FROM fields AS f, form_fields AS ff WHERE ff.is_deleted = FALSE AND f.is_deleted = FALSE AND ff.fields_id = f.id AND ff.forms_id = ? ORDER BY ff.sortorder,f.sortorder,ff.id,f.id;",
                                  $data->{id} )
        or die $dbis->error;
    $self->stash( hash => $data, fields => $fields_it );
    $self->render;
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
    my $it = $dbis->select( 'forms', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    $self->render_not_found unless( $it->rows );
    my $data = $it->hash;

    my $fields_it = $dbis->query( "SELECT f.*, ff.sortorder AS p_sortorder FROM fields AS f, form_fields AS ff WHERE ff.is_deleted = FALSE AND f.is_deleted = FALSE AND ff.fields_id = f.id AND ff.forms_id = ? ORDER BY ff.sortorder,f.sortorder;",
                                  $data->{id} )
        or die $dbis->error;
    $self->stash( hash => $data, fields => $fields_it );
    $self->render();
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
    
    $dbis->update( 'forms', { is_deleted => 1, date_deleted => 'now' }, { id => $id } )
        or die $dbis->error;
    $dbis->update( 'form_fields', { is_deleted => 1, date_deleted => 'now' }, { forms_id => $id } )
        or die $dbis->error;
    $dbis->query( "UPDATE fields SET is_deleted = TRUE, date_deleted = 'now' WHERE is_global = FALSE AND id IN ( SELECT fields_id FROM form_fields WHERE forms_id = ? )", $id )
        or die $dbis->error;
    $dbis->query( "UPDATE field_options SET is_deleted = TRUE, date_deleted = 'now' WHERE fields_id IN ( SELECT fields_id FROM form_fields WHERE forms_id = ? )", $id )
        or die $dbis->error;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( 'admin/forms' );
}


sub change_status {
    my $self = shift;
    my $id   = $self->stash('id');
    my $type = $self->stash('type');

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    
    $dbis->update( 'forms', { is_published => ( $type eq 'private' ? 0 : 1 ), date_published => 'now' }, { id => $id } )
         or die $dbis->error;
    
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( '/admin/forms/view/' . $id );
}

sub get_form_setting {
    my $class = shift;
    my $app   = shift;
    my $id_or_key = shift;
    
    die "id_or_key is missing" unless( defined $id_or_key and length( $id_or_key ) );
    my $dbis = DBIx::Simple->new( @{ $app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    my $form;
    if( $id_or_key =~ /^\d+$/) {
        my $it = $dbis->select('forms', ['*'], { is_deleted => 0, id => $id_or_key, is_published => 1 } ) or die $dbis->error;
        $form = $it->hash if( $it->rows );
    }
    unless( defined $form ) {
        my $it = $dbis->select('forms', ['*'], { is_deleted => 0, key => $id_or_key, is_published => 1 } ) or die $dbis->error;
        $form = $it->hash if( $it->rows );
    }
    return undef unless( defined $form );
    
    my $setting = { id => $form->{id},
                    key => $form->{key},
                    name => Mojo::ByteStream->new( $form->{name} )->decode->to_string,
                    fields => { email =>  { is_required => 1,
                                            desc => Mojo::ByteStream->new( 'メールアドレス' )->decode,
                                            name => 'email',
                                            type => 'textfield',
                                            error_check => 'email' }
                              } };
    $setting->{field_list} = [ $setting->{fields}->{email} ];
    
    my $fields_it = $dbis->query( "SELECT f.*, ff.sortorder AS p_sortorder FROM fields AS f, form_fields AS ff WHERE ff.is_deleted = FALSE AND f.is_deleted = FALSE AND ff.fields_id = f.id AND ff.forms_id = ? ORDER BY ff.sortorder, f.sortorder, ff.id, f.id;",
                                  $form->{id} )
        or die $dbis->error;
    while( my $fline = $fields_it->hash ) {
        my $field = { id   => $fline->{id},
                      name => "field_" . $fline->{id},
                      desc => Mojo::ByteStream->new( $fline->{name} )->decode->to_string,
                      type => $fline->{type},
                      is_required => $fline->{is_required},
                      error_check => $fline->{error_check} };
        if( grep( $_ eq $fline->{type}, qw/checkbox radio popup select/ ) ) {
            my $options_it = $dbis->select('field_options', ['*'], { is_deleted => 0, fields_id => $fline->{id} }, { order_by => 'sortorder, id' } )
                or die $dbis->error;
            $field->{options} = [];
            while( my $oline = $options_it->hash ) {
                my $option = { name => Mojo::ByteStream->new( $oline->{name} )->decode->to_string,
                               value => $oline->{id} };
                push( @{ $field->{options} }, $option );
            }
        }
        $setting->{fields}->{ $field->{name} } = $field;
        push( @{ $setting->{field_list} }, $field );
    }
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
    return $setting;
}

1;
