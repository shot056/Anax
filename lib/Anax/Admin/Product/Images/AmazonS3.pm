package Anax::Admin::Product::Images::AmazonS3;

use strict;
use warnings;

use base qw/Class::Accessor::Fast/;

use Amazon::S3;

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
    my $bucket = $self->get_s3_bucket;

    {
        $self->app->dumper( { "file" => $file, "file->headers->content_type" => $file->headers->content_type } );

        my $flg = $bucket->add_key_filename( "$id.$ext", $file->asset->path, { content_type => $file->headers->content_type,
                                                                               acl_short    => 'public-read' } );
        $self->app->log->debug( "add_key_filename : $id.$ext <- " . $file->asset->path . " : " . $flg );
        $params->{base_url} = join('/',
                                   $self->app->config->{AmazonS3}->{base_url},
                                   $self->app->config->{AmazonS3}->{bucket},
                                   "$id.$ext");
        $params->{public_id} = "$id.$ext";
    }
    {
        my $thumb = $self->get_thumbs( $file, $ext );

        my $flg = $bucket->add_key_filename( "thumbs/$id.$ext", $thumb->path, { content_type => $file->headers->content_type,
                                                                                acl_short    => 'public-read' } );

        $self->app->log->debug( "add_key_filename : thumbs/$id.$ext <- " . $thumb->path . " : " . $flg );
        $params->{thumb_url} = join('/',
                                    $self->app->config->{AmazonS3}->{base_url},
                                    $self->app->config->{AmazonS3}->{bucket},
                                    "thumbs",
                                    "$id.$ext");
    }
    $self->app->dumper( { params => $params } );
    return $params;
}

sub remove {
    my $self = shift;
    my $path = shift;

    my $bucket = $self->get_s3_bucket;

    return ( $bucket->delete_key( $path ) and $bucket->delete_key( "thumbs/$path" ) );
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


sub get_thumbs {
    my $self = shift;
    my $file = shift;
    my $ext  = shift;
    
    unless( $file->asset->is_file ) {
        my $asset = Mojo::Asset::File->new;
        $asset->add_chunk( $file->slurp );
        $file->asset( $asset );
    }
    my $img = Imager->new;
    $img->read( file => $file->asset->path ) or die $img->errstr;
    if( $img->getwidth > 250 or $img->getheight > 250 ) {
        $img = $img->scale( xpixels => 250, ypixels => 250, type => 'min' );
        $img->filter( type => 'unsharpmask', stddev => 1 );
    }
    
    my $fname = "/tmp/thumb_" . $$.".".time().rand( 999 );
    
    $img->write( file => $fname, type => $ext eq 'jpg' ? 'jpeg' : $ext ) or die "Cannot write:" . $img->errstr;
    my $tmp_asset = Mojo::Asset::File->new( path => $fname );
    my $rt = Mojo::Asset::File->new->add_chunk( $tmp_asset->slurp );
    unlink $fname;
    return $rt;
}

sub get_s3_bucket {
    my $self = shift;

    $self->app->log->debug( "conntect to amazon S3" );
    $self->app->dumper( $self->app->config->{AmazonS3} );

#    my $s3 = Net::Amazon::S3->new( $self->app->config->{AmazonS3}->{auth} );
    my $s3 = Amazon::S3->new( $self->app->config->{AmazonS3}->{auth} );
    
#    my $client = Net::Amazon::S3::Client->new( s3 => $s3 );
#    return $client->bucket( name => $self->app->config->{AmazonS3}->{bucket} );
    
#    return $s3->bucket( $self->app->config->{AmazonS3}->{bucket} );

    return $s3->bucket( $self->app->config->{AmazonS3}->{bucket} );
}

1;
