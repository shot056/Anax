package Anax::Admin::Product::Images;

use strict;
use warnings;

use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';

use UNIVERSAL::require;

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

my $vc = Validator::Custom::Anax->new;

sub input {
    my $self       = shift;
    my $product_id = $self->stash('products_id');
    my $id         = $self->stash('id');

    my $params = $self->req->params->to_hash;
    if( defined $id and $id =~ /^\d+$/ ) {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        
        my $rslt = $dbis->select('product_images', ['*'], { id => $id, is_deleted => 0 } )
            or die $dbis->error;
        return $self->render_not_found unless( $rslt->rows );
        $params = $rslt->hash;
        
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
    }
    $self->stash( messages => {}, params => $params );
    $self->render;
}

sub register {
    my $self       = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');
    
    my $params = $self->req->params->to_hash;
    my $upload = $self->param('file');
    my ( $basename, $ext );
    my $content_type;

    if( defined $upload ) {
        $params->{file} = $upload->filename;
        ( $basename, $ext ) = split/\./, $upload->filename;
        $content_type = $upload->headers->content_type;
        $self->app->log->debug( Dumper( $upload->headers ) );
    }
    $self->app->log->info( "params : " . Dumper( $params ) );
    my $rule = [
                name => [ [ 'not_blank', '必ず入力してください' ] ],
                file => [ [ 'not_blank', '必ず入力してください' ] ],
                content_type  => [ [ 'image', 'アップロードできる画像はjpgかgifかpngです' ] ]
               ];
    my $vrslt = $vc->validate( { %{ $params }, content_type => $content_type || '' }, $rule );
    $self->app->log->debug( Dumper( { vrslt => $vrslt, is_ok => $vrslt->is_ok } ) );
    unless( $vrslt->is_ok ) {
        $self->stash( missing => 1 ) if( $vrslt->has_missing );
        $self->stash( messages => $vrslt->messages_to_hash )
            if( $vrslt->has_invalid );
        $self->stash( params => $params );
        $self->app->log->debug( Dumper( $self->stash ) );
        
        $self->render( 'admin/product/images/input' );
    }
    else {
        my $dbis = $self->dbis;
        $dbis->begin_work or die $dbis->error;
        if( $content_type eq 'image/jpeg' ) {
            $ext = 'jpg';
        }
        my $hash = { name        => $params->{name},
                     basename    => $basename,
                     ext         => $ext,
                     description => $params->{description},
                     products_id => $product_id
                   };
        if( defined $id and $id =~ /^\d+$/ ) {
            $hash->{date_updated} = 'now';
            $dbis->update( 'product_images', $hash, { id => $id } )
                or die $dbis->error;
        }
        else {
            $dbis->insert( 'product_images', $hash )
                or die $dbis->error;
            $id = $dbis->last_insert_id( undef, 'public', 'product_images', 'id' ) or die $dbis->error;
        }

        my $res = $self->save_to_cloudinary( $self->param('file') );
        $self->app->log->debug( Dumper( { res => $res } ) );
        my $thumb_url = sprintf("https://res.cloudinary.com/%s/%s/%s/c_limit,h_250,w_250/v%s/%s.%s",
                                $self->app->config->{Cloudinary}->{cloud_name},
                                $res->{resource_type},
                                $res->{type},
                                $res->{version},
                                $res->{public_id},
                                $res->{format} );
        
        $dbis->update( 'product_images',
                       { url => $res->{secure_url},
                         thumb_url => $thumb_url,
                         width => $res->{width},
                         height => $res->{height},
                         public_id => $res->{public_id} },
                       { id => $id } )
            or die $dbis->error;
        
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( '/admin/products/view/' . $product_id );
        
        # my $flag = 0;
        # $self->render_later;
        # Mojo::IOLoop->delay(
        #     sub {
        #         my $delay = shift;
        #         $self->cloudinary_upload( {
        #             file => $self->param('file'),
        #         }, $delay->begin );
        #     },
        #     sub {
        #         my $delay = shift;
        #         my $res   = shift;
        #         my $tx    = shift;
        #         $self->app->log->debug( Dumper( { res => $res } ) );
        #         my $thumb_url = sprintf("https://res.cloudinary.com/%s/%s/%s/c_limit,h_250,w_250/v%s/%s.%s",
        #                                 $self->app->config->{Cloudinary}->{cloud_name},
        #                                 $res->{resource_type},
        #                                 $res->{type},
        #                                 $res->{version},
        #                                 $res->{public_id},
        #                                 $res->{format} );

        #         $dbis->update( 'product_images',
        #                        { url => $res->{secure_url},
        #                          thumb_url => $thumb_url,
        #                          width => $res->{width},
        #                          height => $res->{height},
        #                          public_id => $res->{public_id} },
        #                        { id => $id } )
        #             or die $dbis->error;
                
        #         $dbis->commit or die $dbis->error;
        #         $dbis->disconnect or die $dbis->error;
        #         $self->redirect_to( '/admin/products/view/' . $product_id );
        #         $flag = 1;
        #     }
        # );
    }
}

sub disable {
    my $self       = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    
    my $rslt = $dbis->select('product_images', ['*'], { id => $id, is_deleted => 0 } )
        or die $dbis->error;
    return $self->render_not_found unless( $rslt->rows );
    my $data = $rslt->hash;
    $self->stash( hash => $data );
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    
    $self->render;
}

sub do_disable {
    my $self = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $it = $dbis->select('product_images', ['*'], { id => $id } )
        or die $dbis->error;
    return $self->render_not_found unless( $it->rows );
    
    my $data = $it->hash;
    $dbis->delete( 'product_images', { id => $id } )
        or die $dbis->error;
    
#    my $file_class = 'Anax::Admin::File::' . $self->app->config->{file}->{class};
#    $file_class->use or die "can not use $file_class : $@";
#    my $file_obj = $file_class->new( $self->app );
#    $file_obj->remove( "products/$product_id/images/", "$id.$data->{ext}" );

    if( length( $data->{public_id} ) ) {
        $self->app->log->debug( "destory cloudinary file : $data->{public_id}" );
        $self->remove_from_cloudinary( $data->{public_id} );
        
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( "/admin/products/view/$product_id" );
#        $self->render_later;
#        Mojo::IOLoop->delay(
#            sub {
#                my $delay = shift;
#                $self->cloudinary_destroy( {
#                    public_id => $data->{public_id}
#                }, $delay->begin );
#            },
#            sub {
#                my $delay = shift;
#                my $res   = shift;
#                my $tx    = shift;
#                
#                $dbis->commit or die $dbis->error;
#                $dbis->disconnect or die $dbis->error;
#                $self->redirect_to( "/admin/products/view/$product_id" );
#            } );
    }
    else {
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( "/admin/products/view/$product_id" );
    }
}

sub to_thumbnail {
    my $self = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;
    $dbis->update( 'product_images', { is_thumbnail => 0 }, { products_id => $product_id } )
        or die $dbis->error;
    $dbis->update( 'product_images', { is_thumbnail => 1 }, { id => $id } )
        or die $dbis->error;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( "/admin/products/view/$product_id" );
}


sub not_thumbnail {
    my $self = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;
    $dbis->update( 'product_images', { is_thumbnail => 0 }, { products_id => $product_id, id => $id } )
        or die $dbis->error;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( "/admin/products/view/$product_id" );
}



use Cloudinary;

sub save_to_cloudinary {
    my $self = shift;
    my $file = shift;

    my $data = {};
    if( UNIVERSAL::isa( $file, 'Mojo::Asset' ) ) {
        $data->{file} = { file => $file, filename => basename( $file->path ) };
    }
    elsif( UNIVERSAL::isa( $file, 'Mojo::Upload' ) ) {
        $data->{file} = { file => $file->asset, filename => $file->filename };
    }

    return $self->call_cloudinary( 'upload', $data );
}

sub remove_from_cloudinary {
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
                               api_key => $self->config->{Cloudinary}->{api_key},
                               api_secret => $self->config->{Cloudinary}->{api_secret} );
    $data->{api_key}   = $self->config->{Cloudinary}->{api_key};
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
