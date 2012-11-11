package Validator::Custom::Anax;

use strict;
use warnings;

use base 'Validator::Custom';

use Email::Valid;

sub new {
    my $self = shift->SUPER::new( @_ );
    $self->register_constraint(
                               email => sub {
                                   my $val = shift;
                                   return 1 unless( defined $val and length( $val ) );
                                   my $is_valid;

                                   $is_valid = 1 if( Email::Valid->address( $val ) );
                                   return $is_valid;
                               },
                               integer => sub {
                                   my $val = shift;
                                   return 1 unless( defined $val and length( $val ) );
                                   my $is_valid;
                                   
                                   $is_valid = 1 if( $val =~ /^\d+$/ );
                                   return $is_valid;
                               },
                               ascii => sub {
                                   my $val = shift;
                                   return 1 unless( defined $val and length( $val ) );
                                   my $is_valid;
                                   
                                   $is_valid = 1 if( $val =~ /^\w+$/ );
                                   return $is_valid;
                               },
                               image => sub {
                                   my $val = shift;
                                   return 1 unless( defined $val and length( $val ) );
                                   my $is_valid;
                                   $is_valid = 1 if( grep( $val eq $_, qw!image/jpeg! ) );
                                   return $is_valid;
                               }
                              );
    return $self;
}


1;
