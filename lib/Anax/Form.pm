package Anax::Form;

use strict;
use warnings;
use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';
use Anax::Admin::Forms;
use Tenjin;
use CGI qw/:any/;

use DBIx::Simple;
use SQL::Maker;


use Data::Dumper;

my $vc = Validator::Custom::Anax->new;

sub input {
    my $self = shift;
    my $key = $self->stash('formkey');
    
    my $form_setting = Anax::Admin::Forms->get_form_setting( $self->app, $key );
    #$self->app->log->debug( "settings : \n" . Dumper( $form_setting ) );
    $self->render_not_found unless( defined $form_setting );
    
    my $params = $self->req->params->to_hash;
    #$self->app->log->debug( "params : \n" . Dumper( $params ) );

    my $forms = $self->generate_forms( $form_setting->{field_list}, $params );
    
    my $datas = { action_base => "/form/$key",
                  name        => $form_setting->{name},
                  forms       => $forms,
                  field_list  => $form_setting->{field_list},
                  fields      => $form_setting->{fields},
                  params      => $params
                };
    #$self->app->log->debug( Dumper( $datas ) );
    $self->render( text => $self->render_template( $key, 'input', $datas ) );
}

sub confirm {
    my $self = shift;
    my $key = $self->stash('formkey');
    
    my $form_setting = Anax::Admin::Forms->get_form_setting( $self->app, $key );
    #$self->app->log->debug( "settings : \n" . Dumper( $form_setting ) );
    $self->render_not_found unless( defined $form_setting );
    
    my $params = $self->req->params->to_hash;
    #$self->app->log->debug( "params : \n" . Dumper( $params ) );

    
    my $datas = { action_base => "/form/$key",
                  name        => $form_setting->{name},
                  field_list  => $form_setting->{field_list},
                  fields      => $form_setting->{fields},
                  params      => $params
                };
    my $rule = $self->generate_rule( $form_setting->{field_list} );

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
        $datas->{forms} = $self->generate_forms( $form_setting->{field_list}, $params, 1 );
        
        #$self->app->log->debug( Dumper( $datas ) );
        $self->render( text => $self->render_template( $key, 'confirm', $datas ) );
    }
}

sub complete {
    my $self = shift;
    my $key = $self->stash('formkey');
    
    my $form_setting = Anax::Admin::Forms->get_form_setting( $self->app, $key );
    #$self->app->log->debug( "settings : \n" . Dumper( $form_setting ) );
    $self->render_not_found unless( defined $form_setting );
    
    my $params = $self->req->params->to_hash;
    #$self->app->log->debug( "params : \n" . Dumper( $params ) );
    
    my $datas = { action_base => "/form/$key",
                  name        => $form_setting->{name},
                  field_list  => $form_setting->{field_list},
                  fields      => $form_setting->{fields},
                  params      => $params
                };
    
    my $rule = $self->generate_rule( $form_setting->{field_list} );

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
        $dbis->insert('applicants', { email => $params->{email} } )
            or die $dbis->error;
        my $applicant_id = $dbis->last_insert_id( undef, 'public', 'applicants', 'id' );
        $dbis->insert('applicant_form', { applicants_id => $applicant_id, forms_id => $form_setting->{id} } )
            or die $dbis->error;
        my $applicant_form_id = $dbis->last_insert_id( undef, 'public', 'applicant_form', 'id' );
        foreach my $field ( @{ $form_setting->{field_list} } ) {
            next if( $field->{name} eq 'email' );
            my %hash = ( applicant_form_id => $applicant_form_id,
                         applicants_id => $applicant_id,
                         forms_id => $form_setting->{id},
                         fields_id => $field->{id} );
            if( $field->{type} =~ /^text/ ) {
                $dbis->insert('applicant_data', { %hash, text => $params->{ $field->{name} } } )
                    or die $dbis->error;
            }
            else {
                my $values = $params->{ $field->{name} };
                $values = [ $values ] unless( ref( $values ) eq 'ARRAY' );
                foreach my $value ( @{ $values } ) {
                    $dbis->insert('applicant_data', { %hash, field_options_id => $value } )
                        or die $dbis->error;
                }
            }
        }
        $self->render( text => $self->render_template( $key, 'complete', $datas ) );
        $dbis->commit;
        $dbis->disconnect or die $dbis->error;

    }
}

sub generate_rule {
    my $self   = shift;
    my $fields = shift;
    return [];
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
        if( $field->{type} eq 'hidden' ) {
            $method = 'hidden';
            $mopts{'-value'} = $mopts{'-default'};
            $label = $mopts{'-default'};
            delete $mopts{'-default'};
        }
        elsif( $field->{type} =~ /^text/ ) {
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
            }

            if( defined $mopts{'-default'} ) {
                $mopts{'-default'} = [ $mopts{'-default'} ]
                    unless( ref( $mopts{'-default'} ) eq 'ARRAY' );
                $label = join(", ", map { $mopts{'-labels'}->{ $_ } } @{ $mopts{'-default'} } );
            }
        }
        if( $is_hidden ) {
            $fields{ $field->{name} } = $cgi->hidden( -name => $mopts{'-name'}, -value => $mopts{'-default'} ) . CGI::escapeHTML( $label );
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
    return $tenjin->render( $file, $data );
#    return Mojo::ByteStream->new( $out )->decode;
}

1;
