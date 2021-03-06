package Anax::Form;

use strict;
use warnings;
use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::ByteStream 'b';
use Anax::Mail;
use Anax::Admin::Forms;
use Anax::Admin::Products;
use Tenjin;
use CGI qw/:any/;

use DBIx::Simple;
use SQL::Maker;
use Parallel::ForkManager;

use Data::Dumper;

my $vc = Validator::Custom::Anax->new;

sub input {
    my $self = shift;
    my $key = $self->stash('formkey');
    
    my $params = $self->req->params->to_hash;

    $params->{products} = [ $params->{products} ]
        if( exists $params->{products} and defined $params->{products} and ref( $params->{products} ) ne 'ARRAY' );
    
    #$self->app->log->debug( "params : \n" . Dumper( $params ) );
    
    my $form_setting = Anax::Admin::Forms->new( $self )->get_form_setting( $self->app, $key, $params->{is_admin} );
    $self->app->log->debug( "settings : \n" . Dumper( $form_setting ) );
    return $self->render_not_found unless( defined $form_setting );
    
    my $products     = Anax::Admin::Products->new( $self )->get_form_products( $self->app, $form_setting->{id} );
    $self->app->log->debug( "products : \n" . Data::Dumper->new( [ $products ] )->Sortkeys( 1 )->Dump );

    my $forms = $self->generate_forms( $form_setting->{field_list}, $params );
    
    my $datas = { action_base     => "/form/$key",
                  name            => $form_setting->{name} || '',
                  description     => $form_setting->{description} || '',
                  message         => $form_setting->{messages}->{input} || '',
                  forms           => $forms,
                  field_list      => $form_setting->{field_list},
                  fields          => $form_setting->{fields},
                  product_list    => $products->{list},
                  products        => $products->{hash},
                  product_message => $form_setting->{product_message} || '',
                  has_products    => scalar @{$products->{list}} ? 1 : 0,
                  params          => $params,
                  mail_from       => $self->app->config->{gmail}->{username},
                  use_product_image => $form_setting->{use_product_image},
                  use_product_detail => $form_setting->{use_product_detail},
                  use_product_price => $form_setting->{use_product_price},
                  use_tag           => $form_setting->{use_tag},
                  get_path => sub { return $self->get_path( @_ ) },
                  html_br => sub { return $self->app->html_br( @_ ) }
                };
    $self->app->log->debug( Dumper( $datas ) );
    $self->render( text => $self->render_template( $key, 'input', $datas ) );
}

sub confirm {
    my $self = shift;
    my $key = $self->stash('formkey');
    
    my $params = $self->req->params->to_hash;
    $params->{products} = [ $params->{products} ]
        if( exists $params->{products} and defined $params->{products} and ref( $params->{products} ) ne 'ARRAY' );
    
    #$self->app->log->debug( "params : \n" . Dumper( $params ) );
    
    my $form_setting = Anax::Admin::Forms->new( $self )->get_form_setting( $self->app, $key, $params->{is_admin} );
    #$self->app->log->debug( "settings : \n" . Dumper( $form_setting ) );
    return $self->render_not_found unless( defined $form_setting );
    
    my $products     = Anax::Admin::Products->new( $self )->get_form_products( $self->app, $form_setting->{id} );
    
    
    my $datas = { action_base     => "/form/$key",
                  name            => $form_setting->{name} || '',
                  use_tag         => $form_setting->{use_tag},
                  description     => $form_setting->{description} || '',
                  message         => $form_setting->{messages}->{confirm} || '',
                  field_list      => $form_setting->{field_list},
                  fields          => $form_setting->{fields},
                  product_list    => $products->{list},
                  products        => $products->{hash},
                  product_message => $form_setting->{product_message} || '',
                  has_products    => scalar @{$products->{list}} ? 1 : 0,
                  params          => $params,
                  mail_from       => $self->app->config->{gmail}->{username},
                  use_product_image => $form_setting->{use_product_image},
                  use_product_detail => $form_setting->{use_product_detail},
                  use_product_price => $form_setting->{use_product_price},
                  get_path => sub { return $self->get_path( @_ ) },
                  html_br => sub { return $self->app->html_br( @_ ) }
                };
    my $rule = $self->generate_rule( $form_setting->{field_list} );
    
    my $vresult = $vc->validate( $params, $rule );
    unless( $vresult->is_ok ) {
        $self->stash( missing => 1 ) if( $vresult->has_missing );
        $self->stash( messages => $vresult->messages_to_hash );
        $datas->{messages} = $vresult->messages_to_hash
            if( $vresult->has_invalid );
        $datas->{message} = $form_setting->{messages}->{input} || '';
        $datas->{forms} = $self->generate_forms( $form_setting->{field_list}, $params );
        
        #$self->app->log->debug( Dumper( $datas ) );
        $self->render( text => $self->render_template( $key, 'input', $datas) );
    }
    else {
        $datas->{forms} = $self->generate_forms( $form_setting->{field_list}, $params, 1 );
        
        #$self->app->log->debug( Dumper( $datas ) );
        $self->render( text => $self->render_template( $key, 'confirm', $datas ) );
    }
}

sub complete {
    my $self = shift;
    my $key = $self->stash('formkey');
    
    my $params = $self->req->params->to_hash;
    $params->{products} = [ $params->{products} ]
        if( exists $params->{products} and defined $params->{products} and ref( $params->{products} ) ne 'ARRAY' );
    
    #$self->app->log->debug( "params : \n" . Dumper( $params ) );
    
    my $form_setting = Anax::Admin::Forms->new( $self )->get_form_setting( $self->app, $key, $params->{is_admin} );
    #$self->app->log->debug( "settings : \n" . Dumper( $form_setting ) );
    return $self->render_not_found unless( defined $form_setting );
    
    my $products     = Anax::Admin::Products->new( $self )->get_form_products( $self->app, $form_setting->{id} );

    my $datas = { action_base     => "/form/$key",
                  key             => $key,
                  name            => $form_setting->{name},
                  description     => $form_setting->{description} || '',
                  message         => $form_setting->{messages}->{complete} || '',
                  field_list      => $form_setting->{field_list},
                  fields          => $form_setting->{fields},
                  product_list    => $products->{list},
                  products        => $products->{hash},
                  product_message => $form_setting->{product_message} || '',
                  has_products    => scalar @{$products->{list}} ? 1 : 0,
                  params          => $params,
                  mail_from       => $self->app->config->{gmail}->{username},
                  use_product_image => $form_setting->{use_product_image},
                  use_product_detail => $form_setting->{use_product_detail},
                  use_product_price => $form_setting->{use_product_price},
                  use_tag           => $form_setting->{use_tag},
                  use_tag           => $form_setting->{use_tag},
                  get_path => sub { return $self->get_path( @_ ) },
                  html_br => sub { return $self->app->html_br( @_ ) }
                };
    $datas->{values} = $self->replace_params2value( $form_setting, $products, $params );
#    $self->app->log->debug( "values : \n" . Dumper( $datas->{values} ) );
    
#    $self->app->log->debug( Dumper( $datas ) );
    
    my $rule = $self->generate_rule( $form_setting->{field_list} );
#    $self->app->log->debug( "rule : \n" . Dumper( $rule ) );
    
    my $vresult = $vc->validate( $params, $rule );
    unless( $vresult->is_ok ) {
        $self->stash( missing => 1 ) if( $vresult->has_missing );
        $self->stash( messages => $vresult->messages_to_hash )
            if( $vresult->has_invalid );
        
        $datas->{forms} = $self->generate_forms( $form_setting->{field_list}, $params );
        #$self->app->log->debug( Dumper( $datas ) );
        
        $self->render( text => $self->render_template( $key, 'input', $datas ) );
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        $self->db_insert( $dbis,'applicants', { email => $params->{email} } ) or die $dbis->error;
        my $applicant_id = $dbis->last_insert_id( undef, 'public', 'applicants', 'id' );
        $self->db_insert( $dbis,'applicant_form', { applicants_id => $applicant_id, forms_id => $form_setting->{id} } ) or die $dbis->error;
        my $applicant_form_id = $dbis->last_insert_id( undef, 'public', 'applicant_form', 'id' );
        
        if( $datas->{has_products} ) {
            foreach my $product_id ( @{ $params->{products} } ) {
                $self->db_insert( $dbis, 'applicant_form_products', { applicants_id => $applicant_id,
                                                                   forms_id => $form_setting->{id},
                                                                   applicant_form_id => $applicant_form_id,
                                                                   products_id => $product_id,
                                                                   number => exists $params->{'product:' . $product_id} ? $params->{'product:' . $product_id} : 1
                                                                  } ) or die $dbis->error;
            }
        }
        foreach my $field ( @{ $form_setting->{field_list} } ) {
            next if( $field->{name} eq 'email' );
            my %hash = ( applicant_form_id => $applicant_form_id,
                         applicants_id => $applicant_id,
                         forms_id => $form_setting->{id},
                         fields_id => $field->{id} );
            next unless( exists $params->{ $field->{name} } );
            #$self->app->log->debug( "\$params->{ \$field->{name} } : $field->{name} : \n" . Dumper( $params->{ $field->{name} } ) );
            if( $field->{type} =~ /^text/ ) {
                $self->db_insert( $dbis,'applicant_data', { %hash, text => $params->{ $field->{name} } } ) or die $dbis->error;
            }
            else {
                my $values = $params->{ $field->{name} };
                $values = [ $values ] unless( ref( $values ) eq 'ARRAY' );
                foreach my $value ( @{ $values } ) {
                    $self->app->log->debug( Dumper( { %hash, value => $value } ) );
                    $self->db_insert( $dbis,'applicant_data', { %hash, field_options_id => $value } ) or die $dbis->error;
                }
            }
        }
        my $mail_templates_it = $self->db_select( $dbis,'mail_templates', ['id'], { is_deleted => 0, forms_id => $form_setting->{id} } )
            or die $dbis->error;
        my $mail_parts;
        my $mail_charset;
        my $mail;
        if( $mail_templates_it->rows ) {
            my $id = $mail_templates_it->hash->{id};
            $mail = Anax::Mail->new( $self->app );
            my $tmpl = $mail->load( $id );
            $mail_charset = $tmpl->{charset};
            $mail_parts = $mail->render( $id, $tmpl, $datas );
        }
        $self->render( text => $self->render_template( $key, 'complete', $datas ) );
        $dbis->commit;
        $dbis->disconnect or die $dbis->error;


        if( defined $mail_parts ) {
            my $pm = Parallel::ForkManager->new( 1 );
            foreach( 0 ) {
                my $pid = $pm->start and next;
                $mail->sendmail( $mail_charset, $mail_parts, $datas->{key} );
                $pm->finish;
            }
            $pm->wait_all_children;
        }

    }
}

sub generate_rule {
    my $self   = shift;
    my $fields = shift;
    #$self->app->log->debug( Dumper( $fields ) );

    # my %msgs = ( email => b( '正しいメールアドレスを入力してください。' ),
    #              integer => b( '半角数字で入力してください。' ),
    #              ascii => b( '半角英数字で入力してください。' ) );
#    my %msgs = ( email => b( '正しいメールアドレスを入力してください。' )->decode->to_string,
#                 integer => b( '半角数字で入力してください。' )->decode->to_string,
#                 ascii => b( '半角英数字で入力してください。' )->decode->to_string );
    my %msgs = ( email => '正しいメールアドレスを入力してください。',
                 integer => '半角数字で入力してください。',
                 ascii => '半角英数字で入力してください。' );
    my $rules = [];
    foreach my $f ( @{ $fields } ) {
        my $c = [];
        if( exists $f->{is_required} and defined $f->{is_required} and $f->{is_required} ) {
#            push( @{ $c }, [ 'not_blank', b( '必ず入力してください。' ) ] );
#            push( @{ $c }, [ 'not_blank', b( '必ず入力してください。' )->decode->to_string ] );
            push( @{ $c }, [ 'not_blank', '必ず入力してください。' ] );
        }
        if( exists $f->{error_check} and defined $f->{error_check} and length( $f->{error_check} ) ) {
            push( @{ $c }, [ $f->{error_check}, $msgs{ $f->{error_check} } ] );
        }
        push( @{ $rules }, $f->{name} => $c ) if( scalar @{ $c } );
    }
    return $rules;
}

sub replace_params2value {
    my $self         = shift;
    my $form_setting = shift;
    my $products     = shift;
    my $params       = shift;

    my $ret = {};
    
    foreach my $key ( keys( %{$params} ) ) {
        if( $key =~ /^field_\d+$/ and !( $form_setting->{fields}->{$key}->{type} =~ /^text/ ) ) {
            if( $form_setting->{fields}->{$key}->{type} eq 'radio' ) {
                foreach my $opts ( grep( $_->{value} == $params->{$key}, @{ $form_setting->{fields}->{$key}->{options} } ) ) {
                    $ret->{$key} = $opts->{name};
                }
            }
            else {
                my $vals = $params->{$key};
                $vals = [ $vals ] unless( ref( $vals ) eq 'ARRAY' );
                my $arys = [];
                foreach my $val ( @{ $vals } ) {
                    foreach my $opts ( grep( $_->{value} == $val, @{ $form_setting->{fields}->{$key}->{options} } ) ) {
                        push( @{ $arys }, $opts->{name} );
                    }
                }
                $ret->{$key} = join(', ', @{ $arys } );;
            }
        }
        elsif( $key eq 'products' ) {
            my $prods = $params->{$key};
            $prods = [ $prods ] unless( ref( $prods ) eq 'ARRAY' );
            my $arys = [];
            foreach my $prod ( @{ $prods } ) {
                push( @{ $arys }, $products->{hash}->{$prod}->{name} );
            }
            $ret->{$key} = $arys;
        }
        else {
            $ret->{ $key } = $params->{$key};
        }
    }
    return $ret;
}

sub generate_forms {
    my $self      = shift;
    my $fields    = shift;
    my $params    = shift;
    my $is_hidden = shift || 0;
    
    my $cgi = CGI->new;
    my %fields;
    foreach my $field ( @{ $fields } ) {
        my %mopts = ( -name => $field->{name},
                      -default => $params->{ $field->{name} } || $field->{default} || undef );
        my $label = '';
        my $method;
        next if( $is_hidden and !( exists $params->{ $field->{name} } ) );
        if( $field->{type} eq 'hidden' ) {
            $method = 'hidden';
            $mopts{'-value'} = $mopts{'-default'};
            $label = $mopts{'-default'};
            delete $mopts{'-default'};
        }
        elsif( $field->{type} =~ /^text/ ) {
            $mopts{'-class'} = "form-control";
            $method = $field->{type};
            $label = $mopts{'-default'};
        }
        elsif( grep( $_ eq $field->{type}, qw/checkbox radio popup select/ ) ) {
            my @values;
            my %labels;
            foreach my $opt ( @{ $field->{options} } ) {
                push( @values, $opt->{value} );
                $labels{$opt->{value}} = $opt->{name};
            }
            $mopts{'-values'} = \@values;
            $mopts{'-labels'} = \%labels;
            if( grep( $_ eq $field->{type}, qw/checkbox radio/ ) ) {
                $method = $field->{type} . '_group';
            }
            elsif( $field->{type} eq 'popup' ) {
                $method = 'popup_menu';
            }
            elsif( $field->{type} eq 'select' ) {
                $method = 'scrolling_list';
                $mopts{'-size'}     = 4;
                $mopts{'-multiple'} = 'true';
                $mopts{'-class'} = "form-control";
            }

            if( defined $mopts{'-default'} ) {
                $mopts{'-default'} = [ $mopts{'-default'} ]
                    unless( ref( $mopts{'-default'} ) eq 'ARRAY' );
                $label = join(", ", map { $mopts{'-labels'}->{ $_ } } @{ $mopts{'-default'} } );
            }
        }
        $self->app->log->debug( Dumper( \%mopts ) );
        if( $is_hidden ) {
            my $value = $mopts{'-default'};
            $value = "$value"
                unless( ref( $value ) eq 'ARRAY' or ref( $value ) eq 'SCALAR' );
            $fields{ $field->{name} } = $cgi->hidden( -name => $mopts{'-name'}, -value => $value );
            $label = CGI::escapeHTML( $label );
            if( defined $label ) {
                $label =~ s/\r\n/\n/g;
                $label =~ s/\n/<br \/>\n/g;
            }
            $fields{ $field->{name} } .= $label || '';
        }
        else {
            $fields{ $field->{name} } = $cgi->$method( %mopts );
        }
    }
    return \%fields;
}

sub get_template_file {
    my $self = shift;
    my $key  = shift;
    my $type = shift;

    my $dir  = "templates/form/";
    my $file = "$type.html";
    if( -f $self->app->home->rel_file( "public/tmpls/forms/$key/$type.html" ) ) {
        $dir  = "public/tmpls/forms/$key/";
        $file = "$type.html";
    }
    return ( $dir, $file );
}

sub render_template {
    my $self = shift;
    my $key  = shift;
    my $type = shift;
    my $data = shift;

    my ( $dir, $file ) = $self->get_template_file( $key, $type );
    my $tenjin = Tenjin->new( { path => [ "$dir" ] } );
    return $tenjin->render( $file, $self->v_decode( $data ) );
#    return Mojo::ByteStream->new( $out )->decode;
}

1;
