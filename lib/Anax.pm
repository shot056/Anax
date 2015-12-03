package Anax;

use strict;
use warnings;

use Mojo::Base 'Mojolicious';
use Mojo::ByteStream;
use DateTime::Format::Pg;
use CGI qw/:any/;
use Data::Visitor::Callback;
use Mojo::Path;
use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

use Anax::DBResultWrap;

sub mkrandstr {
    my @s = ( "a" .. "z", "A" .. "Z", 0 .. 9, "!", "|" );
    my $r = "";
    while( length( $r ) < 20 ) {
        $r .= $s[ sprintf( "%d", rand($#s) ) ]
    }
    return $r;
}

# This method will run once at server start
sub startup {
    my $self = shift;

#    $self->app->log->level('debug');
    
    my $fields = { hash => {},
                   array => [
                             { value => 'textfield', label => 'テキストフィールド' },
                             { value => 'checkbox',  label => 'チェックボックス' },
                             { value => 'radio',     label => 'ラジオ' },
                             { value => 'popup',     label => 'ポップアップ' },
                             { value => 'select',    label => 'セレクト' },
                             { value => 'textarea',  label => 'テキストエリア' }
                            ] };
    foreach my $f ( @{ $fields->{array} } ) {
        $fields->{hash}->{ $f->{value} } = $f->{label};
    }
    my $error_checks = { hash => {},
                         array => [
                                   { value => '',        label => 'なし' },
                                   { value => 'integer', label => '半角数字' },
                                   { value => 'ascii',   label => '半角英数字' },
                                   { value => 'email',   label => 'メールアドレス' }
                                  ] };
    foreach my $e ( @{ $error_checks->{array} } ) {
        $error_checks->{hash}->{ $e->{value} } = $e->{label};
    }
    
    $self->app->secrets( [ mkrandstr(), mkrandstr(), mkrandstr() ] );
    
    # Documentation browser under "/perldoc"
    # $self->plugin('PODRenderer');
    $self->plugin('Config');
    #$self->plugin('TagHelpers');
    $self->plugin('CSRFDefender');
    $self->plugin('Cloudinary',
                  { cloud_name => $self->config->{Cloudinary}->{cloud_name},
                    api_key => $self->config->{Cloudinary}->{api_key},
                    api_secret => $self->config->{Cloudinary}->{api_secret}
                  } );

    $self->helper( b => sub {
                       my $self = shift;
                       my $str  = shift;
                       $str = '' unless( defined $str );
                       return Mojo::ByteStream->new( $str );
                   } );
    $self->helper( decode => sub {
                       my $self = shift;
                       my $str  = shift;
                       return '' unless( defined $str and length( $str ) );
                       my $undef = undef;
                       my $ret = Mojo::ByteStream->new( $str )->decode->to_string;
                       return ( ( defined $ret and length( $ret ) ) ? $ret : $str );
                   } );
    my $v_decode = Data::Visitor::Callback->new(
                                                plain_value => sub {
                                                    my $str = shift;
                                                    my $ret = &{$self->renderer->helpers->{decode}}( $self, $_ );
                                                    return "$ret";
                                                }
                                               );
    $self->helper( v_decode => sub {
                       my $self = shift;
                       my $data = shift;
                       return $v_decode->visit( $data );
                   } );
    $self->helper( encode => sub {
                       my $self = shift;
                       my $str  = shift;
                       return '' unless( defined $str and length( $str ) );
                       my $undef = undef;
                       my $ret = Mojo::ByteStream->new( $str )->encode->to_string;
                       return ( ( defined $ret and length( $ret ) ) ? $ret : $str );
                   } );
    my $v_encode = Data::Visitor::Callback->new(
                                                plain_value => sub {
                                                    my $str = shift;
                                                    my $ret = &{$self->renderer->helpers->{encode}}( $self, $_ );
                                                    return "$ret";
                                                }
                                               );
    $self->helper( v_encode => sub {
                       my $self = shift;
                       my $data = shift;
                       return $v_encode->visit( $data );
                   } );
    my $v_b = Data::Visitor::Callback->new(
                                           plain_value => sub {
                                               my $str = shift;
                                               return &{$self->renderer->helpers->{b}}( $self, $_ );
                                           } );
    $self->helper( v_b => sub {
                       my $self = shift;
                       my $data = shift;
                       return $v_b->visit( $data );
                   } );
    $self->helper( date => sub {
                       my $self = shift;
                       my $date = shift;
                       return '----' unless( defined $date and length( $date ) );
                       my $dt = DateTime::Format::Pg->parse_timestamp_with_time_zone( $date );
                       $dt->set_time_zone( 'Asia/Tokyo' );
                       return sprintf('%04d-%02d-%02d %02d:%02d',
                                      $dt->year, $dt->month, $dt->day, $dt->hour, $dt->minute );
                   } );
    $self->helper( field_types => sub {
                       my $self = shift;
                       my $key  = shift;
                       if( defined $key ) {
                           return $fields->{hash}->{$key} || 'ERROR';
                       }
                       else {
                           return $fields->{array};
                       }
                   } );
    $self->helper( error_checks => sub {
                       my $self = shift;
                       my $key  = shift;
                       if( defined $key ) {
                           return $error_checks->{hash}->{$key} || 'ERROR';
                       }
                       else {
                           return $error_checks->{array};
                       }
                   } );
    $self->helper( html_br => sub {
                       my $self = shift;
                       my $str  = shift;
                       return '' unless( defined $str and length( $str ) );
                       my $ret = Mojo::ByteStream->new( $str )->xml_escape;
                       $ret =~ s/\r\n/\n/g;
                       $ret =~ s/\n/<br \/>\n/g;
                       return $ret;
                   } );
    $self->helper( cgi => sub {
                      my $self    = shift;
                      my $method  = shift;
                      my $options = shift;
                      
                      unless( defined $self->stash( '__cgi_object' ) ) {
                          $self->stash( '__cgi_object', CGI->new );
                      }
                      return '' unless( $self->stash( '__cgi_object' )->can( $method ) );
                      my $opts = $v_decode->visit( $options );
                      return $self->stash( '__cgi_object' )->$method( %{ $opts } );
                  } );
    $self->helper( dbis => sub {
                       my $self = shift;

                       my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
                           or die DBIx::Simple->error;
                       $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
                       return $dbis;
                   } );
    $self->helper( dumper => sub {
                       my $self = shift;
                       return $self->app->log->debug( Data::Dumper->new( \@_ )->Sortkeys( 1 )->Dump );
                   } );
    $self->helper( get_path => sub {
                       my $self = shift;
                       my @paths = @_;
                       my $path = Mojo::Path->new( $ENV{MOJO_PREFIX} || '' )->leading_slash( 1 );
                       foreach my $p ( @paths ) {
#                           $self->dumper( { p => $p, path => $path } );
                           $path = $path->trailing_slash( 1 )->merge( Mojo::Path->new( $p )->leading_slash( 0 ) )
                       }
                       return $path->to_abs_string;
                   } );
    $self->helper( db_insert => sub {
                       my $self  = shift;
                       my $dbis  = shift;
                       my $table = shift;
                       my $data  = shift;
                       return $dbis->insert( $table, $self->v_encode( $data ) )
                   } );
    $self->helper( db_update => sub {
                       my $self   = shift;
                       my $dbis   = shift;
                       my $table  = shift;
                       my $data   = shift;
                       my $wheres = shift;
                       return $dbis->update( $table, $self->v_encode( $data ), $self->v_encode( $wheres ) );
                   } );
    $self->helper( db_select => sub {
                       my $self    = shift;
                       my $dbis    = shift;
                       my $table   = shift;
                       my $columns = shift;
                       my $wheres  = shift || {};
                       my $options = shift || {};

                       my $it = $dbis->select( $table, $columns, $wheres, $options ) or return undef;
                       return Anax::DBResultWrap->new( $self->app, $it );
                   } );
    $self->helper( db_query_select => sub {
                       my $self = shift;
                       my $dbis = shift;
                       my $sql  = shift;
                       my @bind = @_;

                       my $it = $dbis->query( $sql, @bind ) or return undef;
                       return Anax::DBResultWrap->new( $self->app, $it );
                   } );
    $self->app->sessions->secure( 1 )
        unless( $self->app->config->{unsecure_session} );
    $self->app->sessions->cookie_name('anax_session');
    # Router
    my $r = $self->routes;

    $r = $r->bridge->to( cb => sub {
        my $self = shift;

        $self->app->log->info( "++++++++++++++++++++ Start Request ++++++++++++++++++++" );
        $self->app->log->info( "Request: " . $self->req->method . " " . $self->req->url->to_string );
        $self->app->log->info( "Params : \n" . Data::Dumper->new( [ $self->req->params->to_hash ] )->Sortkeys( 1 )->Dump );
        $self->app->log->info( "Session: \n" . Data::Dumper->new( [ $self->session ] )->Sortkeys( 1 )->Dump );
        
        return 1 unless( $self->req->url->to_string =~ m!^/admin! );
        return 1 if( $self->req->url->to_string eq '/admin/login' );
        if( $self->session('is_logged_in') ) {
            return 1;
        }
        else {
            $self->redirect_to( $self->get_path( '/admin/login' ) );
            return 0;
        }
    } );
    # Normal route to controller
#    $r->get('/')->to('example#welcome');

#    $r->get('/:id')->to('form#input');
    $r->get('/')->to( controller => 'Home', action => 'index' );
    
    $r->route('/form/:formkey',          id => qr/\w+/ )->via('GET','POST' )->to( controller => 'Form', action => 'input' );
    $r->route('/form/:formkey/confirm',  id => qr/\w+/ )->via('POST')->to( controller => 'Form', action => 'confirm' );
    $r->route('/form/:formkey/complete', id => qr/\w+/ )->via('POST')->to( controller => 'Form', action => 'complete' );

    $r->route('/admin')->via('GET')->to( controller => 'Admin', action => 'index' );
    
    $r->route('/admin/login' )->via('GET' )->to( controller => 'Admin', action => 'login' );
    $r->route('/admin/login' )->via('POST')->to( controller => 'Admin', action => 'do_login' );
    $r->route('/admin/logout')->via('GET' )->to( controller => 'Admin', action => 'logout' );
    
    $r->route('/admin/forms'                            )->via('GET' )->to( controller => 'Admin::Forms', action => 'index' );
    $r->route('/admin/forms/add'                        )->via('GET' )->to( controller => 'Admin::Forms', action => 'input' );
    $r->route('/admin/forms/add'                        )->via('POST')->to( controller => 'Admin::Forms', action => 'register' );
    $r->route('/admin/forms/edit/:id',    id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Forms', action => 'input' );
    $r->route('/admin/forms/edit/:id',    id => qr/\d+/ )->via('POSt')->to( controller => 'Admin::Forms', action => 'register' );
    $r->route('/admin/forms/view/:id',    id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Forms', action => 'view' );
    $r->route('/admin/forms/disable/:id', id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Forms', action => 'disable' );
    $r->route('/admin/forms/disable/:id', id => qr/\d+/ )->via('POSt')->to( controller => 'Admin::Forms', action => 'do_disable' );
    
    $r->route('/admin/forms/changestatus/:id/:type', id => qr/\d+/, type => qr/(publish|private)/ )
        ->via('GET')->to( controller => 'Admin::Forms', action => 'change_status' );
    
    $r->route('/admin/fields'                            )->via('GET' )->to( controller => 'Admin::Fields', action => 'index' );
    $r->route('/admin/fields/add'                        )->via('GET' )->to( controller => 'Admin::Fields', action => 'input' );
    $r->route('/admin/fields/add'                        )->via('POST')->to( controller => 'Admin::Fields', action => 'register' );
    $r->route('/admin/fields/edit/:id',    id => qr/[0-9]+/ )->via('GET' )->to( controller => 'Admin::Fields', action => 'input' );
    $r->route('/admin/fields/edit/:id',    id => qr/\d+/ )->via('POSt')->to( controller => 'Admin::Fields', action => 'register' );
    $r->route('/admin/fields/view/:id',    id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Fields', action => 'view' );
    $r->route('/admin/fields/disable/:id', id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Fields', action => 'disable' );
    $r->route('/admin/fields/disable/:id', id => qr/\d+/ )->via('POSt')->to( controller => 'Admin::Fields', action => 'do_disable' );
    $r->route('/admin/fields/associate/:form_id', form_id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Fields', action => 'associate' );
    $r->route('/admin/fields/associate/:form_id', form_id => qr/\d+/ )->via('POST')->to( controller => 'Admin::Fields', action => 'do_associate' );

    $r->route('/admin/field/:field_id/options/add', field_id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Field::Options', action => 'input' );
    $r->route('/admin/field/:field_id/options/add', field_id => qr/\d+/ )->via('POST')->to( controller => 'Admin::Field::Options', action => 'register' );

    $r->route('/admin/mailtemplates/add'                     )->via('GET' )->to( controller => 'Admin::MailTemplates', action => 'input' );
    $r->route('/admin/mailtemplates/add'                     )->via('POST')->to( controller => 'Admin::MailTemplates', action => 'register' );
    $r->route('/admin/mailtemplates/edit/:id', id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::MailTemplates', action => 'input' );
    $r->route('/admin/mailtemplates/edit/:id', id => qr/\d+/ )->via('POST')->to( controller => 'Admin::MailTemplates', action => 'register' );
    
    $r->route('/admin/products'                         )->via('GET' )->to( controller => 'Admin::Products', action => 'index' );
    $r->route('/admin/products/add'                     )->via('GET' )->to( controller => 'Admin::Products', action => 'input' );
    $r->route('/admin/products/add'                     )->via('POST')->to( controller => 'Admin::Products', action => 'register' );
    $r->route('/admin/products/edit/:id', id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Products', action => 'input' );
    $r->route('/admin/products/edit/:id', id => qr/\d+/ )->via('POST')->to( controller => 'Admin::Products', action => 'register' );
    $r->route('/admin/products/view/:id', id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Products', action => 'view' );

    $r->route('/admin/products/associate/:form_id', form_id => qr/\d+/ )->via('GET')->to( controller => 'Admin::Products', action => 'associate' );
    $r->route('/admin/products/associate/:form_id', form_id => qr/\d+/ )->via('POST')->to( controller => 'Admin::Products', action => 'do_associate' );
    
    $r->route('/admin/product/:product_id/images/add',              product_id => qr/\d+/                )
        ->via('GET' )->to( controller => 'Admin::Product::Images', action => 'input' );
    $r->route('/admin/product/:product_id/images/add',              product_id => qr/\d+/                )
        ->via('POST')->to( controller => 'Admin::Product::Images', action => 'register' );
    $r->route('/admin/product/:product_id/images/disable/:id',      product_id => qr/\d+/, id => qr/\d+/ )
        ->via('GET' )->to( controller => 'Admin::Product::Images', action => 'disable' );
    $r->route('/admin/product/:product_id/images/disable/:id',      product_id => qr/\d+/, id => qr/\d+/ )
        ->via('POST')->to( controller => 'Admin::Product::Images', action => 'do_disable' );
    $r->route('/admin/product/:product_id/images/to_thumbnail/:id', product_id => qr/\d+/, id => qr/\d+/ )
        ->via('POST')->to( controller => 'Admin::Product::Images', action => 'to_thumbnail' );
    $r->route('/admin/product/:product_id/images/not_thumbnail/:id', product_id => qr/\d+/, id => qr/\d+/ )
        ->via('POST')->to( controller => 'Admin::Product::Images', action => 'not_thumbnail' );
    
    $r->route('/admin/mailwizard/select'   )->via('POST')->to( controller => 'Admin::MailWizard', action => 'select_target' );
    $r->route('/admin/mailwizard/template' )->via('POST')->to( controller => 'Admin::MailWizard', action => 'template_input' );
    $r->route('/admin/mailwizard/confirm'  )->via('POST')->to( controller => 'Admin::MailWizard', action => 'confirm' );
    $r->route('/admin/mailwizard/send'     )->via('POST')->to( controller => 'Admin::MailWizard', action => 'send_mail' );
    
    $r->route('admin/applicants'                                                             )->via('GET' )->to( controller => 'Admin::Applicants', action => 'index' );
    $r->route('admin/applicants'                                                             )->via('POST')->to( controller => 'Admin::Applicants', action => 'index' );
    $r->route('admin/applicants/view/:id/:form_id',    id => qr/\d+/, form_id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Applicants', action => 'view' );
    $r->route('admin/applicants/disable/:id/:form_id', id => qr/\d+/, form_id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Applicants', action => 'disable' );
    $r->route('admin/applicants/disable/:id/:form_id', id => qr/\d+/, form_id => qr/\d+/ )->via('POST')->to( controller => 'Admin::Applicants', action => 'do_disable' );

    $r->route('admin/sort/:target/:id', id => qr/\d+/, target => qr/[a-z_]+/ )->via('GET' )->to( controller => 'Admin::Sort', action => 'edit' );
    $r->route('admin/sort/:target/:id', id => qr/\d+/, target => qr/[a-z_]+/ )->via('POST')->to( controller => 'Admin::Sort', action => 'do_edit' );
}

1;
