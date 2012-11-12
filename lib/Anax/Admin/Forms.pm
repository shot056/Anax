package Anax::Admin::Forms;

use strict;
use warnings;
use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;
use Mojo::ByteStream 'b';

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
                     description => $params->{description},
                     product_message => $params->{product_message},
                     message_input => $params->{message_input},
                     message_confirm => $params->{message_confirm},
                     message_complete => $params->{message_complete},
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

    my $products_it = $dbis->query( "SELECT p.* FROM products AS p, form_products AS fp WHERE p.is_deleted = FALSE AND fp.is_deleted = FALSE AND fp.products_id = p.id AND fp.forms_id = ? ORDER BY fp.sortorder, fp.id, p.id",
                                    $data->{id} )
        or die $dbis->error;
    
    my $mail_template = undef;
    my $mail_templates_it = $dbis->select( 'mail_templates', ['*'], { is_deleted => 0, forms_id => $id } )
        or die $dbis->error;
    $mail_template = $mail_templates_it->hash if( $mail_templates_it->rows );
    
    $self->stash( hash => $data, fields => $fields_it, products => $products_it, mail_template => $mail_template );
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
    my $class     = shift;
    my $app       = shift;
    my $id_or_key = shift;
    my $is_admin  = shift || 0;
    
    die "id_or_key is missing" unless( defined $id_or_key and length( $id_or_key ) );
    my $dbis = DBIx::Simple->new( @{ $app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    my $form;
    if( $id_or_key =~ /^\d+$/) {
        my $wheres = { is_deleted => 0, id => $id_or_key, is_published => 1 };
        delete $wheres->{is_published} if( $is_admin );
        
        my $it = $dbis->select('forms', ['*'], $wheres ) or die $dbis->error;
        $form = $it->hash if( $it->rows );
    }
    unless( defined $form ) {
        my $wheres = { is_deleted => 0, key => $id_or_key, is_published => 1 };
        delete $wheres->{is_published} if( $is_admin );
        my $it = $dbis->select('forms', ['*'], $wheres ) or die $dbis->error;
        $form = $it->hash if( $it->rows );
    }
    return undef unless( defined $form );
    
    my $setting = { id => $form->{id},
                    key => $form->{key},
                    name => b( $form->{name} )->decode->to_string,
                    description => b( $form->{description} || '' )->decode->to_string,
                    product_message => b( $form->{product_message} || '' )->decode->to_string,
                    messages => { input => b( $form->{message_input} || '' )->decode->to_string,
                                  confirm => b( $form->{message_confirm} || '' )->decode->to_string,
                                  complete => b( $form->{message_complete} || '' )->decode->to_string },
                    fields => { email =>  { is_required => 1,
                                            desc => b( 'メールアドレス' )->decode->to_string,
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
                      desc => b( $fline->{name} )->decode->to_string,
                      type => $fline->{type},
                      default => b( $fline->{default} )->decode->to_string || undef,
                      is_required => $fline->{is_required},
                      error_check => $fline->{error_check} };
        if( grep( $_ eq $fline->{type}, qw/checkbox radio popup select/ ) ) {
            my $options_it = $dbis->select('field_options', ['*'], { is_deleted => 0, fields_id => $fline->{id} }, { order_by => 'sortorder, id' } )
                or die $dbis->error;
            $field->{options} = [];
            $field->{options_hash} = {};
            while( my $oline = $options_it->hash ) {
                my $option = { name => b( $oline->{name} )->decode->to_string,
                               value => $oline->{id} };
                push( @{ $field->{options} }, $option );
                $field->{options_hash}->{ $oline->{id} } = b( $oline->{name} )->decode->to_string;
            }
        }
        $setting->{fields}->{ $field->{name} } = $field;
        push( @{ $setting->{field_list} }, $field );
    }
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
    #$app->log->debug( Dumper( $setting ) );
    return $setting;
}

1;
