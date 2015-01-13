package Anax::Admin::Product::Images::Cloudinary;

use strict;
use warnings;

use base qw/Class::Accessor::Fast/;

use Cloudinary;
use Data::Dumper;

sub new {
    my $pkg = shift;
    my $app = shift;
    my $self = bless( {}, $pkg );
    $self->mk_accessors( qw/app/ );
    $self->app( $app );
    
    return $self;
}

sub save {
    my $self = shift;
    my $file = shift;

    my $data = {};
    if( UNIVERSAL::isa( $file, 'Mojo::Asset' ) ) {
        $data->{file} = { file => $file, filename => basename( $file->path ) };
    }
    elsif( UNIVERSAL::isa( $file, 'Mojo::Upload' ) ) {
        $data->{file} = { file => $file->asset, filename => $file->filename };
    }

    my $res = $self->call_cloudinary( 'upload', $data );
    $self->app->log->debug( Dumper( { res => $res } ) );
    return {
        thumb_url => sprintf("https://res.cloudinary.com/%s/%s/%s/c_limit,h_250,w_250/v%s/%s.%s",
                             $self->app->config->{Cloudinary}->{cloud_name},
                             $res->{resource_type},
                             $res->{type},
                             $res->{version},
                             $res->{public_id},
                             $res->{format} ),
        base_url => $res->{secure_url},
        width => $res->{width},
        height => $res->{height},
        public_id => $res->{public_id}
    };
}

sub remove {
    my $self      = shift;
    my $public_id = shift;

    my $data = { public_id => $public_id, type => 'upload' };

    return $self->call_cloudinary( 'destroy', $data );
}

sub call_cloudinary {
    my $self   = shift;
    my $action = shift;
    my $data   = shift;

    my $cdn = Cloudinary->new( cloud_name => $self->app->config->{Cloudinary}->{cloud_name},
                               api_key => $self->app->config->{Cloudinary}->{api_key},
                               api_secret => $self->app->config->{Cloudinary}->{api_secret} );
    $data->{api_key}   = $self->app->config->{Cloudinary}->{api_key};
    $data->{timestamp} = time;
    $data->{signature} = $cdn->_api_sign_request( $data );
    
    my $url = join( '/', ( 'http://api.cloudinary.com/v1_1',
                           $self->app->config->{Cloudinary}->{cloud_name},
                           'image',
                           $action ) );
    my $headers = { 'Content-Type' => 'multipart/form-data' };

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->post( $url, $headers, form => $data );
    return $tx->res->json || { error => $tx->error || 'Unknown error' };
}

1;
