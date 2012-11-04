package Anax::Home;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';

sub index {
    my $self = shift;

    $self->render;
}

1;
