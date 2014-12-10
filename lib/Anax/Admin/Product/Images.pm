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
                content_type  => [ [ 'image', 'アップロードできる画像はjpgかjpegかpngです' ] ]
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
        $self->app->log->debug( "++++++++++++++++++++ 1" );
        my $dbis = $self->dbis;
        $dbis->begin_work or die $dbis->error;
        $self->app->log->debug( "++++++++++++++++++++ 2" );
        if( $content_type eq 'image/jpeg' ) {
            $ext = 'jpg';
        }
        $self->app->log->debug( "++++++++++++++++++++ 3" );
        my $hash = { name        => $params->{name},
                     basename    => $basename,
                     ext         => $ext,
                     description => $params->{description},
                     products_id => $product_id
                   };
        $self->app->log->debug( "++++++++++++++++++++ 4" );
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
        $self->app->log->debug( "++++++++++++++++++++ 5" );

        $self->render_later;
        Mojo::IOLoop->delay(
            sub {
                $self->app->log->debug( "++++++++++++++++++++ 6" );
                my $delay = shift;
                $self->cloudinary_upload( {
                    file => $self->param('file'),
                }, $delay->begin );
            },
            sub {
                $self->app->log->debug( "++++++++++++++++++++ 7" );
                my $delay = shift;
                my $res   = shift;
                my $tx    = shift;
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
            }
        );
        $self->app->log->debug( "++++++++++++++++++++ -2" );
    }
    $self->app->log->debug( "++++++++++++++++++++ -1" );
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
        $self->render_later;
        Mojo::IOLoop->delay(
            sub {
                my $delay = shift;
                $self->cloudinary_destroy( {
                    public_id => $data->{public_id}
                }, $delay->begin );
            },
            sub {
                my $delay = shift;
                my $res   = shift;
                my $tx    = shift;
                
                $dbis->commit or die $dbis->error;
                $dbis->disconnect or die $dbis->error;
                $self->redirect_to( "admin/products/view/$product_id" );
            } );
    }
    else {
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( "admin/products/view/$product_id" );
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
    $self->redirect_to( "admin/products/view/$product_id" );
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
    $self->redirect_to( "admin/products/view/$product_id" );
}


1;
