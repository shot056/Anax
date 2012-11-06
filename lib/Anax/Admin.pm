package Anax::Admin;

use Mojo::Base 'Mojolicious::Controller';

sub index {
    my $self = shift;
    my $todo = $self->app->home->slurp_rel_file('ToDo');
    $self->stash( todo => $todo );
    my $changes = $self->app->home->slurp_rel_file('Changes');
    $self->stash( changes => $changes );
    
    $self->render;
}


1;
