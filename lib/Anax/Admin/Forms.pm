package Anax::Admin::Forms;

use strict;
use warnings;
use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;
use Mojo::ByteStream;

my $vc = Validator::Custom::Anax->new;

sub b {
    my $str = shift;
    $str = '' unless( defined $str );
    return Mojo::ByteStream->new( $str );
}

sub index {
    my $self = shift;
    $self->app->log->debug( Dumper( $self->app->config ) );
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $rslt = $dbis->select( 'forms', ['*'], { is_deleted => 0 }, { order_by => 'name' } )
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
    my $dbis      = shift;
    
    die "id_or_key is missing" unless( defined $id_or_key and length( $id_or_key ) );
    my $dbis_is_not_defined;
    unless( defined $dbis ) {
        $dbis_is_not_defined = 1;
        $dbis = DBIx::Simple->new( @{ $app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
    }

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
#                    name => $form->{name},
#                    description => $form->{description} || '',
#                    product_message => $form->{product_message} || '',
#                    messages => { input => $form->{message_input} || '',
#                                  confirm => $form->{message_confirm} || '',
#                                  complete => $form->{message_complete} || '' },
                    name => b( $form->{name} ),
                    description => b( $form->{description} || '' ),
                    product_message => b( $form->{product_message} || '' ),
                    messages => { input => b( $form->{message_input} || '' ),
                                  confirm => b( $form->{message_confirm} || '' ),
                                  complete => b( $form->{message_complete} || '' ) },
                    # name => b( $form->{name} )->decode->to_string,
                    # description => b( $form->{description} || '' )->decode->to_string,
                    # product_message => b( $form->{product_message} || '' )->decode->to_string,
                    # messages => { input => b( $form->{message_input} || '' )->decode->to_string,
                    #               confirm => b( $form->{message_confirm} || '' )->decode->to_string,
                    #               complete => b( $form->{message_complete} || '' )->decode->to_string },
                    fields => {
#                               email =>  { is_required => 1,
#                                           desc => b( 'メールアドレス' )->decode->to_string,
#                                           name => 'email',
#                                           type => 'textfield',
#                                           error_check => 'email' }
                              } };
    $setting->{field_list} = [
#                              $setting->{fields}->{email}
                             ];
    
    my $fields_it = $dbis->query( "SELECT f.*, ff.sortorder AS p_sortorder FROM fields AS f, form_fields AS ff WHERE ff.is_deleted = FALSE AND f.is_deleted = FALSE AND ff.fields_id = f.id AND ff.forms_id = ? ORDER BY ff.sortorder, f.sortorder, ff.id, f.id;",
                                  $form->{id} )
        or die $dbis->error;
    while( my $fline = $fields_it->hash ) {
        my $field = $class->get_field_data( $dbis, $fline );
        $setting->{fields}->{ $field->{name} } = $field;
        push( @{ $setting->{field_list} }, $field );
    }
    if( $dbis_is_not_defined ) {
        $dbis->commit;
        $dbis->disconnect or die $dbis->error;
        #$app->log->debug( Dumper( $setting ) );
    }
    return $setting;
}

sub get_field_data {
    my $self = shift;
    my $dbis = shift;
    my $line = shift;

    my $field = { id          => $line->{id},
                  name        => "field_" . $line->{id},
#                  desc        => $line->{name},
#                  desc        => b( $line->{name} )->decode->to_string,
                  desc        => b( $line->{name} ),
                  type        => $line->{type},
                  default     => $line->{default} || undef,
                  default     => b( $line->{default} ),
#                  default     => b( $line->{default} )->decode->to_string || undef,
                  is_required => $line->{is_required},
                  is_global   => $line->{is_global},
                  error_check => $line->{error_check} };
    if( grep( $_ eq $line->{type}, qw/checkbox radio popup select/ ) ) {
        ( $field->{options}, $field->{options_hash} ) = $self->get_field_options( $dbis, $line->{id} );
    }
    return $field;
}

sub get_field_options {
    my $self     = shift;
    my $dbis     = shift;
    my $field_id = shift;
    
    
    my $it = $dbis->select('field_options', ['*'], { is_deleted => 0, fields_id => $field_id }, { order_by => 'sortorder, id' } )
        or die $dbis->error;
    
    my $options = [];
    my $options_hash = {};
    while( my $line = $it->hash ) {
        my $option = { name => b( $line->{name} ),
#        my $option = { name => b( $line->{name} )->decode->to_string,
#        my $option = { name => $line->{name},
                       value => $line->{id} };
        push( @{ $options }, $option );
#        $options_hash->{ $line->{id} } = $line->{name};
        $options_hash->{ $line->{id} } = b( $line->{name} );
#        $options_hash->{ $line->{id} } = b( $line->{name} )->decode->to_string;
    }
    return ( $options, $options_hash );
}

sub get_fields {
    my $self = shift;
    my $dbis = shift;
    my $forms_id = shift;
    my $common_only = shift || 0;
    #  select fields_id, count( id ) FROM form_fields WHERE forms_id IN ( SELECT forms_id FROM applicant_form WHERE applicants_id IN ( 1,2,3,4,5,6 ) ) GROUP BY fields_id;

    my $tmp_fields = {};
    {
        my $stmt = SQL::Maker::Select->new;
        $stmt->{new_line} = ' ';
        $stmt->add_select( sprintf( "fields_id, COUNT( id ) = %d AS is_common", scalar @{ $forms_id } ) );
        $stmt->add_from( "form_fields" );
        $stmt->add_where( "is_deleted" => 0 );
        $stmt->add_where( "forms_id" => { IN => $forms_id } );
        $stmt->add_group_by( "fields_id" );
        $self->app->log->debug( "[SQL] " . $stmt->as_sql . "; ( " . join(", ", $stmt->bind ) . " )" );
        
        my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind ) or die $dbis->error;
        while( my $line = $rslt->hash ) {
            next if( $common_only and !$line->{is_common} );
            $tmp_fields->{ $line->{fields_id} } = { is_common => $line->{is_common} };
        }
    }

    my $fields = {};
    my $it = $dbis->select( 'fields', ["*"],{ is_deleted => 0, id => { IN => [ keys( %{ $tmp_fields } ) ] } }, { order_by => 'name, id' } )
        or die $dbis->error;
    while( my $line = $it->hash ) {
        my $field = $self->get_field_data( $dbis, $line );
        my $div = $tmp_fields->{ $line->{id} }->{is_common} ? 'common' : 'individual';
        $fields->{ $div } = { hash => {}, array => [] }
            unless( exists $fields->{ $div } );
        push( @{ $fields->{$div }->{array} }, $field );
        $fields->{$div }->{hash}->{ $field->{id} } = $field;
    }
    return $fields;
}

1;
