package Validator::Custom::Anax;


use base 'Validator::Custom';

sub new {
    my $self = shift->SUPER::new( @_ );
    $self->register_constraint(
                               ascii => sub {
                                   my $val = shift;
                                   my $is_valid;
                                   
                                   $is_valid = 1 if( $val =~ /^\w+$/ );
                                   return $is_valid;
                               },
                               
                              );
    return $self;
}


1;
