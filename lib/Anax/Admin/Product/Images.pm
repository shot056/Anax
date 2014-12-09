package Anax::Admin::Product::Images;

use strict;
use warnings;

use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';

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
        $self->render_not_found unless( $rslt->rows );
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
        my $store_dir = $self->app->home->rel_dir("public/static/products/$product_id/images/");
        $self->app->log->info( "store_dir : $store_dir" );
        $self->app->commands->create_dir( $store_dir )
            unless( -d $store_dir );
        my $target_file = $self->app->home->rel_file( "public/static/products/$product_id/images/$id.$ext" );
        $self->app->log->info( "store to : $target_file" );
        $upload->move_to( "public/static/products/$product_id/images/$id.$ext" );
        
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( '/admin/products/view/' . $product_id );
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
    $self->render_not_found unless( $rslt->rows );
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
    $self->render_not_found unless( $it->rows );
    
    my $data = $it->hash;
    $dbis->delete( 'product_images', { id => $id } )
        or die $dbis->error;
    unlink $self->app->home->rel_file( "public/static/products/$product_id/images/$id.$data->{ext}" )
        or die "can not remove image : public/static/products/$product_id/images/$id.$data->{ext} : $!";
    
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( "admin/products/view/$product_id" );
}

sub to_thumbnail {
    my $self = shift;
    my $product_id = $self->stash('product_id');
    my $id         = $self->stash('id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;
    $dbis->update( 'product_images', { use_thumbnail => 0 }, { products_id => $product_id } )
        or die $dbis->error;
    $dbis->update( 'product_images', { use_thumbnail => 1 }, { id => $id } )
        or die $dbis->error;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( "admin/products/view/$product_id" );
}

1;
