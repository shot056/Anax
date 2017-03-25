package Anax::DBResultWrap;

use strict;
use warnings;

use base 'Class::Accessor::Fast';

sub new {
    my $pkg = shift;
    my $app = shift;
    my $it  = shift;
    
    my $self = bless( {}, $pkg );
    $self->mk_accessors( qw/app it/ );
    $self->app( $app );
    $self->it( $it );
    
    return $self;
}

sub rows {
    return shift->it->rows;
}

sub hash {
    my $self = shift;
    return $self->app->v_decode( $self->it->hash );
}

sub hashes {
    my $self = shift;
    my $result = $self->app->v_decode( [ $self->it->hashes ] );
    return wantarray ? @{ $result } : $result;
}

1;
