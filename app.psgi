use strict;
use warnings;
use Mojo::Server::PSGI;
use Plack::Builder;
use FindBin;
use lib "$FindBin::Bin/lib";
use Anax;

my $psgi = Mojo::Server::PSGI->new( app => Anax->new );
my $app = $psgi->to_psgi_app;

builder {
    $app;
};
