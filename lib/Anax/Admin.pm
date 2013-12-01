package Anax::Admin;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub index {
    my $self = shift;
    my $todo = $self->app->home->rel_file('ToDo');
    $self->stash( todo => $todo );
    my $changes = $self->app->home->rel_file('Changes');
    $self->stash( changes => $changes );
    
    $self->render;
}

sub login {
    my $self = shift;
    $self->render;
}

sub do_login {
    my $self = shift;

    my $params = $self->req->params->to_hash;
    if( exists $params->{login_id} and defined $params->{login_id}
        and length( $self->app->config->{login_id} ) > 0 and $params->{login_id} eq $self->app->config->{login_id}
        and exists $params->{password} and defined $params->{password}
        and length( $self->app->config->{password} ) > 0 and $params->{password} eq $self->app->config->{password} ) {

        $self->session( is_logged_in => 1 );
        $self->redirect_to( '/admin' );
    }
    else {
        $self->stash( failure => 1 );
        $self->render( '/admin/login' );
    }
}

sub logout {
    my $self = shift;

    $self->session( is_logged_in => 0 );
    $self->redirect_to( '/admin/login' );
}


1;
