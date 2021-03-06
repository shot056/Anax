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
    my $rslt = $self->db_select( $dbis, 'forms', ['*'], { is_deleted => 0 }, { order_by => 'name' } )
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
        my $rslt = $self->db_select( $dbis,'forms', ['*'], { id => $id, is_deleted => 0 } )
            or die $dbis->error;
        return $self->render_not_found unless( $rslt->rows );
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
                          [ { length => [ 3, 16 ] }, '3文字以上、16文字以下で入力してください' ],
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
        my $hash = { key => $params->{key} || '',
                     name => $params->{name} || '',
                     description => $params->{description} || '',
                     product_message => $params->{product_message} || '',
                     message_input => $params->{message_input} || '',
                     message_confirm => $params->{message_confirm} || '',
                     message_complete => $params->{message_complete} || '',
                     use_product_image => $params->{use_product_image} || 0,
                     use_product_detail => $params->{use_product_detail} || 0,
                     use_product_price => $params->{use_product_price} || 0,
                     use_tag_in_description => $params->{use_tag_in_description} || 0,
                     use_tag_in_message_input => $params->{use_tag_in_message_input} || 0,
                     use_tag_in_message_confirm => $params->{use_tag_in_message_confirm} || 0,
                     use_tag_in_message_complete => $params->{use_tag_in_message_complete} || 0,
#                     is_published => $params->{is_published}
                   };
        if( defined $id and $id =~ /^\d+$/ ) {
            $hash->{date_updated} = 'now';
            $self->db_update( $dbis, 'forms', $hash, { id => $id } ) or die $dbis->error;
        }
        else {
            $self->dumper( { hash => $hash, v_hash => $self->v_decode( $hash ) } );
            $self->db_insert( $dbis, 'forms', $hash ) or die $dbis->error;
        }
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( $self->get_path( '/admin/forms' ) );
    }
}

sub view {
    my $self = shift;
    my $id   = $self->stash('id');
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    my $it = $self->db_select( $dbis, 'forms', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    unless( $it->rows ) {
        $self->render_not_found;
    } else {
        my $data = $it->hash;
#        my $fields_it = $self->db_select( $dbis, 'form_fields', ['*'],
#                                       { is_deleted => 0, forms_id => $data->{id} },
#                                       { order_by => 'sortorder, id' } )
#            or die $dbis->error;
        my $fields_it = $self->db_query_select( $dbis, "SELECT f.*, ff.sortorder AS p_sortorder FROM fields AS f, form_fields AS ff WHERE ff.is_deleted = FALSE AND f.is_deleted = FALSE AND ff.fields_id = f.id AND ff.forms_id = ? ORDER BY ff.sortorder,f.sortorder,ff.id,f.id;",
                                                $data->{id} )
            or die $dbis->error;

        my $products_it = $self->db_query_select( $dbis, "SELECT p.* FROM products AS p, form_products AS fp WHERE p.is_deleted = FALSE AND fp.is_deleted = FALSE AND fp.products_id = p.id AND fp.forms_id = ? ORDER BY fp.sortorder, fp.id, p.id",
                                                  $data->{id} )
            or die $dbis->error;
    
        my $mail_template = undef;
        my $mail_templates_it = $self->db_select( $dbis, 'mail_templates', ['*'], { is_deleted => 0, forms_id => $id } )
            or die $dbis->error;
        $mail_template = $mail_templates_it->hash if( $mail_templates_it->rows );
        
        $self->stash( hash => $data, fields => $fields_it, products => $products_it, mail_template => $mail_template );
        $self->render;
    }
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
    my $it = $self->db_select( $dbis, 'forms', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    unless( $it->rows ) {
        $self->render_not_found;
    } else {
        my $data = $it->hash;
        
        my $fields_it = $self->db_query_select( $dbis, "SELECT f.*, ff.sortorder AS p_sortorder FROM fields AS f, form_fields AS ff WHERE ff.is_deleted = FALSE AND f.is_deleted = FALSE AND ff.fields_id = f.id AND ff.forms_id = ? ORDER BY ff.sortorder,f.sortorder;",
                                                $data->{id} )
            or die $dbis->error;
        $self->stash( hash => $data, fields => $fields_it );
        $self->render();
    }
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
    
    $self->db_update( $dbis, 'forms', { is_deleted => 1, date_deleted => 'now' }, { id => $id } ) or die $dbis->error;
    $self->db_update( $dbis, 'form_fields', { is_deleted => 1, date_deleted => 'now' }, { forms_id => $id } ) or die $dbis->error;
    $dbis->query( "UPDATE fields SET is_deleted = TRUE, date_deleted = 'now' WHERE is_global = FALSE AND id IN ( SELECT fields_id FROM form_fields WHERE forms_id = ? )", $id )
        or die $dbis->error;
    $dbis->query( "UPDATE field_options SET is_deleted = TRUE, date_deleted = 'now' WHERE fields_id IN ( SELECT fields_id FROM form_fields WHERE forms_id = ? )", $id )
        or die $dbis->error;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( $self->get_path( '/admin/forms' ) );
}

sub copy {
    my $self = shift;
    my $id   = $self->stash('id');

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $it = $self->db_select( $dbis, 'forms', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    unless( $it->rows ) {
        $self->render_not_found;
    } else {
        my $data = $it->hash;
        $self->stash( messages => {} );
        $self->render( template => 'admin/forms/copy', params => { id => $id, key => $data->{key} . '_copy', name => $data->{name} . '_copy' } );
    }
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}

sub do_copy {
    my $self = shift;
    my $id   = $self->stash( 'id' );

    my $params = $self->req->params->to_hash;
    my $rule = [
                name => [ [ 'not_blank', '必ず入力してください' ] ],
                key  => [ [ 'not_blank', '必ず入力してください' ],
                          [ { length => [ 3, 16 ] }, '3文字以上、16文字以下で入力してください' ],
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
        $self->render( template => 'admin/forms/copy', params => $params );
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        
        my $form_rslt = $self->db_select( $dbis, 'forms', [ '*' ], { id => $id, is_deleted => 0 } )
            or die $dbis->error;
        unless( $form_rslt->rows ) {
            $self->render_not_found;
        } else {
            {
                my $hash = $form_rslt->hash;
                foreach my $key ( qw/id is_deleted date_created date_updated date_deleted key name is_published date_published / ) {
                    delete $hash->{$key};
                }
                foreach my $key ( qw/name key/ ) {
                    $hash->{$key} = $params->{ $key };
                }
                $self->dumper( { hash => $hash, v_hash => $self->v_decode( $hash ) } );
                my $rslt = $self->db_insert( $dbis, 'forms', $hash ) or die $dbis->error;
            }
            my ( $dbname ) = $self->app->config->{dsn}->[0] =~ m!dbname=([a-zA-Z0-9_]+)!;
            my $form_id = $dbis->last_insert_id( $dbname, 'public', 'forms', 'id' );
            
            my %copy_target = ( 'form_products'  => { delcol => [ qw/id is_deleted date_created date_updated date_deleted forms_id/ ], order => 'sortorder' },
                                'mail_templates' => { delcol => [ qw/id is_deleted date_created date_updated date_deleted forms_id/ ], order => 'id' } );
            foreach my $table ( keys( %copy_target ) ) {
                my $rslt = $self->db_select( $dbis, $table, [ '*' ], { forms_id => $id, is_deleted => 0 }, { order_by => $copy_target{ $table }->{order} } )
                    or die $dbis->error;
                my $sortorder = 1;
                while( my $hash = $rslt->hash ) {
                    foreach my $col ( @{ $copy_target{ $table }->{delcol} } ) {
                        delete $hash->{ $col };
                    }
                    $hash->{forms_id} = $form_id;
                    $hash->{sortorder} = $sortorder
                        if( $table eq 'form_products' );
                    $self->dumper( { hash => $hash, v_hash => $self->v_decode( $hash ) } );
                    $self->db_insert( $dbis, $table, $hash );
                    $sortorder ++;
                }
            }
            {
                my $rslt = $self->db_select( $dbis, 'form_fields', [ '*' ], { forms_id => $id, is_deleted => 0 }, { order_by => 'sortorder' } )
                    or die $dbis->error;
                my $sortorder = 1;
                while( my $hash = $rslt->hash ) {
                    foreach my $col ( qw/id is_deleted date_created date_updated date_deleted forms_id/ ) {
                        delete $hash->{ $col };
                    }
                    $hash->{forms_id} = $form_id;
                    $hash->{sortorder} = $sortorder;
                    my $field_rslt = $self->db_select( $dbis, 'fields', [ '*' ], { id => $hash->{fields_id}, is_deleted => 0 } )
                        or die $dbis->error;
                    if( $field_rslt->rows > 0 ) {
                        my $field = $field_rslt->hash;
                        unless( $field->{is_global} ) {
                            foreach my $key ( qw/id is_delete d date_created date_updated date_deleted sortorder/ ) {
                                delete $field->{$key};
                            }
                            $self->dumper( { hash => $field, v_hash => $self->v_decode( $field ) } );
                            $self->db_insert( $dbis, 'fields', $field )
                                or die $dbis->error;
                            my $fields_id = $dbis->last_insert_id( $dbname, 'public', 'fields', 'id' );
                            unless( $field->{type} =~ /text/ ) {
                                my $opt_rslt = $self->db_select( $dbis, 'field_options', [ '*' ], { fields_id => $hash->{fields_id}, is_deleted => 0 }, { order_by => 'sortorder' } )
                                    or die $dbis->error;
                                my $opt_sortorder = 1;
                                while( my $opthash = $opt_rslt->hash ) {
                                    foreach my $key ( qw/id is_delete d date_created date_updated date_deleted fields_id/ ) {
                                        delete $opthash->{ $key };
                                    }
                                    $opthash->{fields_id} = $fields_id;
                                    $opthash->{sortorder} = $opt_sortorder;
                                    $self->dumper( { hash => $opthash, v_hash => $self->v_decode( $opthash ) } );
                                    $self->db_insert( $dbis, 'field_options', $opthash )
                                        or die $dbis->error;
                                    $opt_sortorder ++;
                                }
                            }
                            $hash->{fields_id} = $fields_id;
                        }
                        $self->dumper( { hash => $hash, v_hash => $self->v_decode( $hash ) } );
                        $self->db_insert( $dbis, 'form_fields', $hash );
                        $sortorder ++;
                    }
                }
            }
            $self->redirect_to( $self->get_path( '/admin/forms/view/' . $form_id ) );
        }
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
    }
}

sub change_status {
    my $self = shift;
    my $id   = $self->stash('id');
    my $type = $self->stash('type');

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    
    $self->db_update( $dbis, 'forms', { is_published => ( $type eq 'private' ? 0 : 1 ), date_published => 'now' }, { id => $id } ) or die $dbis->error;
    
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( $self->get_path( '/admin/forms/view/' . $id ) );
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
        
        my $it = $app->db_select( $dbis,'forms', ['*'], $wheres ) or die $dbis->error;
        $form = $it->hash if( $it->rows );
    }
    unless( defined $form ) {
        my $wheres = { is_deleted => 0, key => $id_or_key, is_published => 1 };
        delete $wheres->{is_published} if( $is_admin );
        my $it = $app->db_select( $dbis,'forms', ['*'], $wheres ) or die $dbis->error;
        $form = $it->hash if( $it->rows );
    }
    return undef unless( defined $form );
    
    my $setting = { id => $form->{id},
                    key => $form->{key},
                    use_tag => { description => $form->{use_tag_in_description} || 0,
                                 message_input => $form->{use_tag_in_message_input} || 0,
                                 message_confirm => $form->{use_tag_in_message_confirm} || 0,
                                 message_complete => $form->{use_tag_in_message_complete} || 0 },
                    use_product_image => $form->{use_product_image} || 0,
                    use_product_detail => $form->{use_product_detail} || 0,
                    use_product_price => $form->{use_product_price} || 0,
                    
                    name => $form->{name},
                    description => $form->{description} || '',
                    product_message => $form->{product_message} || '',
                    messages => { input => $form->{message_input} || '',
                                  confirm => $form->{message_confirm} || '',
                                  complete => $form->{message_complete} || '' },

                    # name => b( $form->{name} || '' ),
                    # description => b( $form->{description} || '' ),
                    # product_message => b( $form->{product_message} || '' ),
                    # messages => { input => b( $form->{message_input} || '' ),
                    #               confirm => b( $form->{message_confirm} || '' ),
                    #               complete => b( $form->{message_complete} || '' ) },
                    
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
    
    my $fields_it = $app->db_query_select( $dbis, "SELECT f.*, ff.sortorder AS p_sortorder FROM fields AS f, form_fields AS ff WHERE ff.is_deleted = FALSE AND f.is_deleted = FALSE AND ff.fields_id = f.id AND ff.forms_id = ? ORDER BY ff.sortorder, f.sortorder, ff.id, f.id;",
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
                  type        => $line->{type},
                  
                  desc        => $line->{name},
                  default     => $line->{default} || '',
                  
                  # desc        => b( $line->{name} || '' ),
                  # default     => b( $line->{default} || '' ),
                  
                  # desc        => b( $line->{name} )->decode->to_string,
                  # default     => b( $line->{default} )->decode->to_string || undef,
                  
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
    
    
    my $it = $self->db_select( $dbis,'field_options', ['*'], { is_deleted => 0, fields_id => $field_id }, { order_by => 'sortorder, id' } )
        or die $dbis->error;
    
    my $options = [];
    my $options_hash = {};
    while( my $line = $it->hash ) {
        my $option = { name => $line->{name},
        # my $option = { name => b( $line->{name} || '' ),
        # my $option = { name => b( $line->{name} )->decode->to_string,
                       value => $line->{id} };
        push( @{ $options }, $option );
        $options_hash->{ $line->{id} } = $line->{name};
        # $options_hash->{ $line->{id} } = b( $line->{name} || '' );
        # $options_hash->{ $line->{id} } = b( $line->{name} )->decode->to_string;
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
        
        my $rslt = $self->db_query_select( $dbis, $stmt->as_sql, $stmt->bind ) or die $dbis->error;
        while( my $line = $rslt->hash ) {
            next if( $common_only and !$line->{is_common} );
            $tmp_fields->{ $line->{fields_id} } = { is_common => $line->{is_common} };
        }
    }

    my $fields = {};
    my $it = $self->db_select( $dbis, 'fields', ["*"],{ is_deleted => 0, id => { IN => [ keys( %{ $tmp_fields } ) ] } }, { order_by => 'name, id' } )
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
