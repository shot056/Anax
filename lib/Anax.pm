package Anax;
use Mojo::Base 'Mojolicious';
use Mojo::ByteStream;
use DateTime::Format::Pg;

use Data::Dumper;

# This method will run once at server start
sub startup {
    my $self = shift;

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
                                   { value => 'ascii',   label => '半角英数字' }
                                  ] };
    foreach my $e ( @{ $error_checks->{array} } ) {
        $error_checks->{hash}->{ $e->{value} } = $e->{label};
    }
    
    $self->secret('oJQFCAli%gfbORcj');
    
    # Documentation browser under "/perldoc"
    # $self->plugin('PODRenderer');
    $self->plugin('Config');
    $self->plugin('TagHelpers');
    $self->plugin('CSRFDefender');
    
    $self->helper( b => sub {
                       my $self = shift;
                       return Mojo::ByteStream->new(@_);
                   } );
    $self->helper( decode => sub {
                       my $self = shift;
                       my $str  = shift;
                       return '' unless( defined $str and length( $str ) );
                       my $ret = Mojo::ByteStream->new( $str )->decode;
                       return length( $ret ) ? $ret : $str;
                   } );
    $self->helper( date => sub {
                       my $self = shift;
                       my $date = shift;
                       return '----' unless( defined $date and length( $date ) );
                       my $dt = DateTime::Format::Pg->parse_timestamp_with_time_zone( $date );
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
                       my $ret = Mojo::ByteStream->new( $str )->html_escape;
                       $ret =~ s/\r\n/\n/g;
                       $ret =~ s/\n/<br \/>\n/g;
                       return $ret;
                   } );
    $self->app->sessions->cookie_name('anax_session');
    # Router
    my $r = $self->routes;

    $r = $r->bridge->to( cb => sub {
        my $self = shift;

        $self->app->log->info( "++++++++++ Start Request ++++++++++" );
        $self->app->log->info( "Request: " . $self->req->url->to_string );
        $self->app->log->info( "Params : \n" . Dumper( $self->req->params->to_hash ) );
        $self->app->log->info( "Session: \n" . Dumper( $self->session ) );
        
        return 1 unless( $self->req->url->to_string =~ m!^/admin! );
        return 1 if( $self->req->url->to_string eq '/admin/login' );
        if( $self->session('is_logged_in') ) {
            return 1;
        }
        else {
            $self->redirect_to( '/admin/login' );
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
    $r->route('/admin/fields/edit/:id',    id => qr/\d+/ )->via('GET' )->to( controller => 'Admin::Fields', action => 'input' );
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
    
    $r->route('/admin/product/:product_id/images/add',         product_id => qr/\d+/                )
        ->via('GET' )->to( controller => 'Admin::Product::Images', action => 'input' );
    $r->route('/admin/product/:product_id/images/add',         product_id => qr/\d+/                )
        ->via('POST')->to( controller => 'Admin::Product::Images', action => 'register' );
    $r->route('/admin/product/:product_id/images/disable/:id', product_id => qr/\d+/, id => qr/\d+/ )
        ->via('GET' )->to( controller => 'Admin::Product::Images', action => 'disable' );
    $r->route('/admin/product/:product_id/images/disable/:id', product_id => qr/\d+/, id => qr/\d+/ )
        ->via('POST')->to( controller => 'Admin::Product::Images', action => 'do_disable' );
    
    
    $r->route('/admin/applicants'                                                      )->via('GET')->to( controller => 'Admin::Applicants', action => 'index' );
    $r->route('/admin/applicants/view/:id/:form_id', id => qr/\d+/, form_id => qr/\d+/ )->via('GET')->to( controller => 'Admin::Applicants', action => 'view' );
}

1;
