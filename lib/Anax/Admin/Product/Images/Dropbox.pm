package Anax::Admin::Product::Images::Dropbox;

use strict;
use warnings;

use base qw/Class::Accessor::Fast/;

use WebService::Dropbox;

use Imager;
use Data::Dumper;

sub new {
    my $pkg = shift;
    my $app = shift;
    
    my $self = bless( {}, $pkg );
    $self->mk_accessors( qw/app/ );
    $self->app( $app );

    return $self;
}

sub get_thumbs {
    my $self = shift;
    my $file = shift;
    
    unless( $file->asset->is_file ) {
        my $asset = Mojo::Asset::File->new;
        $asset->add_chunk( $file->slurp );
        $file->asset( $asset );
    }
    my $img = Imager->new;
    $img->read( file => $file->asset->path ) or die $img->errstr;
    $img = $img->scale( xpixels => 250, ypixels => 250 );
    
    my $thumb_asset = Mojo::Asset::File->new;
    $thumb_asset->handle;#->close;
    
    $img->write( $thumb_asset->path );
    return $thumb_asset;
}

sub save {
    my $self = shift;
    my $file = shift;
    my $id   = shift;
    my $ext  = shift;
    
    unless( $file->asset->is_file ) {
        my $asset = Mojo::Asset::File->new;
        $asset->add_chunk( $file->slurp );
        $file->asset( $asset );
    }
    my $params = {};
    ( $params->{width}, $params->{height} ) = $self->get_wh( $file );
    my $dropbox = $self->get_dropbox;

    {
        my $base_fh = $file->asset->handle;
        my $base_file = $dropbox->files_put( $id . "." . $ext, $base_fh ) or die $dropbox->error;
        $base_fh->close;
#        $self->app->log->debug( Data::Dumper->new( [ { bf => $base_file } ] )->Sortkeys( 1 )->Dump );
        my $base_share = $dropbox->shares( $base_file->{path}, { short_url => 0 } ) or die $dropbox->error;
#        $self->app->log->debug( Data::Dumper->new( [ { bs => $base_share } ] )->Sortkeys( 1 )->Dump );
#        $self->app->dumper( { meta => $dropbox->metadata( $base_file->{path}, { include_media_info => 1 } ) } );
        $params->{base_url} = $base_share->{url};
        $params->{base_url} =~ s!https://www\.!https://dl\.!;
        $params->{base_url} =~ s!\?dl=0$!!;
        $params->{public_id} = $base_file->{path};
    }
    {
        my $thumb = $self->get_thumbs( $file );
#        $self->app->dumper( { thumb => $thumb } );
        my $thumb_fh = $thumb->handle;
        my $thumb_file = $dropbox->files_put( "thumbs/" . $id . "." . $ext, $thumb_fh ) or die $dropbox->error;
        $thumb_fh->close;
#        $self->app->log->debug( Data::Dumper->new( [ { tf => $thumb_file } ] )->Sortkeys( 1 )->Dump );
        my $thumb_share = $dropbox->shares( $thumb_file->{path}, { short_url => 0 } ) or die $dropbox->error;
#        $self->app->log->debug( Data::Dumper->new( [ { ts => $thumb_share } ] )->Sortkeys( 1 )->Dump );
        $params->{thumb_url} = $thumb_share->{url};
        $params->{thumb_url} =~ s!https://www\.!https://dl\.!;
        $params->{thumb_url} =~ s!\?dl=0$!!;
    }
#    $self->app->dumper( { params => $params } );
    return $params;
}

sub remove {
    my $self = shift;
    my $path = shift;

    my $dropbox = $self->get_dropbox;
    return ( $dropbox->delete( $path ) and $dropbox->delete( "/thumbs" . $path ) );
}

sub get_wh {
    my $self = shift;
    my $file = shift;

    unless( $file->asset->is_file ) {
        my $asset = Mojo::Asset::File->new;
        $asset->add_chunk( $file->slurp );
        $file->asset( $asset );
    }
    my $img = Imager->new;
    $img->read( file => $file->asset->path );
    return ( $img->getwidth, $img->getheight );
}

sub get_dropbox {
    my $self = shift;

    my $dropbox = WebService::Dropbox->new( {
        key => $self->app->config->{Dropbox}->{key},
        secret => $self->app->config->{Dropbox}->{secret}
    } );
    unless( exists $self->app->config->{Dropbox}->{access}->{token} and length( $self->app->config->{Dropbox}->{access}->{token} ) > 0
                and exists $self->app->config->{Dropbox}->{access}->{secret} and length( $self->app->config->{Dropbox}->{access}->{secret} ) > 0 ) {
        my $url = $dropbox->login;
        $self->app->log->debug( "Please Access URL and press Enter: $url" );
        sleep( 10 );
        $dropbox->auth or die $dropbox->error;
        $self->app->log->warn( "access_token: " . $dropbox->access_token );
        $self->app->log->warn( "access_secret: " . $dropbox->access_secret );
    }
    else {
        $dropbox->access_token( $self->app->config->{Dropbox}->{access}->{token} );
        $dropbox->access_secret( $self->app->config->{Dropbox}->{access}->{secret} );
    }
    $dropbox->root('sandbox');
    return $dropbox;
}

1;
