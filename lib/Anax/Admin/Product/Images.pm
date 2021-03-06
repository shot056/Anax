package Anax::Admin::Product::Images;

use strict;
use warnings;

use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';

use UNIVERSAL::require;

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

use Anax::Admin::Product::Images::Cloudinary;
use Anax::Admin::Product::Images::Dropbox;
use Anax::Admin::Product::Images::AmazonS3;

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
        
        my $rslt = $self->db_select( $dbis,'product_images', ['*'], { id => $id, is_deleted => 0 } )
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
        elsif( $content_type eq 'image/png' ) {
            $ext = 'png';
        }
        elsif( $content_type eq 'image/gif' ) {
            $ext = 'gif';
        }
        my $hash = { name        => $params->{name},
                     basename    => $basename,
                     ext         => $ext,
                     description => $params->{description},
                     products_id => $product_id
                   };
        if( defined $id and $id =~ /^\d+$/ ) {
            $hash->{date_updated} = 'now';
            $self->db_update( $dbis, 'product_images', $hash, { id => $id } ) or die $dbis->error;
        }
        else {
            $self->db_insert( $dbis, 'product_images', $hash ) or die $dbis->error;
            $id = $dbis->last_insert_id( undef, 'public', 'product_images', 'id' ) or die $dbis->error;
        }

        my $obj;
        if( $self->app->config->{useCloudinary} ) {
            $obj = Anax::Admin::Product::Images::Cloudinary->new( $self->app );
        }
        elsif( $self->app->config->{useDropbox} ) {
            $obj = Anax::Admin::Product::Images::Dropbox->new( $self->app );
        }
        elsif( $self->app->config->{useAmazonS3} ) {
            $obj = Anax::Admin::Product::Images::AmazonS3->new( $self->app );
        }
        if( defined $obj ) {
            my $params = $obj->save( $self->param('file'), $id, $ext );
            $self->db_update( $dbis, 'product_images',
                           { url => $params->{base_url},
                             thumb_url => $params->{thumb_url},
                             width => $params->{width},
                             height => $params->{height},
                             public_id => $params->{public_id} },
                           { id => $id } ) or die $dbis->error;
        }
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( $self->get_path( '/admin/products/view/', $product_id ) );
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
    
    my $rslt = $self->db_select( $dbis,'product_images', ['*'], { id => $id, is_deleted => 0 } )
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
    my $it = $self->db_select( $dbis,'product_images', ['*'], { id => $id } )
        or die $dbis->error;
    return $self->render_not_found unless( $it->rows );
    
    my $data = $it->hash;
    $dbis->delete( 'product_images', { id => $id } )
        or die $dbis->error;
    
#    my $file_class = 'Anax::Admin::File::' . $self->app->config->{file}->{class};
#    $file_class->use or die "can not use $file_class : $@";
#    my $file_obj = $file_class->new( $self->app );
#    $file_obj->remove( "products/$product_id/images/", "$id.$data->{ext}" );

    my $obj;
    if( $self->app->config->{useCloudinary} ) {
        if( length( $data->{public_id} ) ) {
            $self->app->log->debug( "destory cloudinary file : $data->{public_id}" );
            $obj = Anax::Admin::Product::Images::Cloudinary->new( $self->app );
        }
    }
    elsif( $self->app->config->{useDropbox} ) {
        if( length( $data->{public_id} ) ) {
            $self->app->log->debug( "remove dropbox file : $data->{public_id}" );
            $obj = Anax::Admin::Product::Images::Dropbox->new( $self->app );
        }
    }
    elsif( $self->app->config->{useAmazonS3} ) {
        if( length( $data->{public_id} ) ) {
            $self->app->log->debug( "remove amazon s3 file : $data->{public_id}" );
            $obj = Anax::Admin::Product::Images::AmazonS3->new( $self->app );
        }
    }
    if( defined $obj ) {
        $obj->remove( $data->{public_id} );
    }
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
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( $self->get_path( "/admin/products/view/$product_id" ) );
}

sub to_thumbnail {
    my $self = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;
    $self->db_update( $dbis, 'product_images', { is_thumbnail => 0 }, { products_id => $product_id } ) or die $dbis->error;
    $self->db_update( $dbis, 'product_images', { is_thumbnail => 1 }, { id => $id } ) or die $dbis->error;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( $self->get_path( "/admin/products/view/$product_id" ) );
}


sub not_thumbnail {
    my $self = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;
    $self->db_update( $dbis, 'product_images', { is_thumbnail => 0 }, { products_id => $product_id, id => $id } ) or die $dbis->error;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( $self->get_path( "/admin/products/view/$product_id" ) );
}





1;
