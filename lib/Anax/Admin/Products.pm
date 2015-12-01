package Anax::Admin::Products;

use strict;
use warnings;

use utf8;

use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::ByteStream 'b';

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;


my $vc = Validator::Custom::Anax->new;

sub index {
    my $self = shift;
#    $self->app->log->debug( Dumper( $self->app->config ) );
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    
    my $rslt = $dbis->select( 'products', ['*'], { is_deleted => 0 }, { order_by => 'sortorder, id ASC' } )
        or die $dbis->error;
    
    $self->stash( datas => $rslt );
    $self->render();
    
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

sub input {
    my $self = shift;
    my $id   = $self->stash('id');
    
    my $params = $self->req->params->to_hash;
    if( defined $id and $id =~ /^\d+$/ ) {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        
        my $rslt = $dbis->select('products', ['*'], { id => $id, is_deleted => 0 } )
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
    my $self = shift;
    my $id   = $self->stash('id');
    
    my $params = $self->req->params->to_hash;
#    $self->app->log->info( "params : " . Dumper( $params ) );
    my $rule = [
                name  => [ [ 'not_blank', '必ず入力してください' ] ],
                price => [ [ 'not_blank', '必ず入力してください' ],
                           [ 'int',       '半角英数字で入力してください' ] ]
               ];
    my $vrslt = $vc->validate( $params, $rule );
#    $self->app->log->debug( Dumper( { vrslt => $vrslt, is_ok => $vrslt->is_ok } ) );
    unless( $vrslt->is_ok ) {
        $self->stash( missing => 1 ) if( $vrslt->has_missing );
        $self->stash( messages => $vrslt->messages_to_hash )
            if( $vrslt->has_invalid );
        $self->stash( params => $params );
#        $self->app->log->debug( Dumper( $self->stash ) );
        $self->render( 'admin/products/input' );
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        
        my $hash = { price => $params->{price},
                     name => $params->{name},
                     description => $params->{description},
                     use_tag_in_description => $params->{use_tag_in_description} || 0
                   };
        if( defined $id and $id =~ /^\d+$/ ) {
            $hash->{date_updated} = 'now';
            $dbis->update( 'products', $self->v_encode( $hash ), { id => $id } )
                or die $dbis->error;
        }
        else {
            $dbis->insert( 'products', $self->v_encode( $hash ) )
                or die $dbis->error;
            if( exists $params->{forms_id} and $params->{forms_id} =~ /^\d+$/ ) {
                my $products_id = $dbis->last_insert_id( undef, 'public', 'products', 'id' ) or die $dbis->error;
                $dbis->insert( 'form_products', { forms_id => $params->{forms_id}, products_id => $products_id } )
                    or die $dbis->error;
            }
        }
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( $self->get_path( $params->{forms_id} ? '/admin/forms/view/' . $params->{forms_id} : '/admin/products' ) );
    }
}

sub view {
    my $self = shift;
    my $id   = $self->stash('id');
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    
    my $it = $dbis->select( 'products', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    return $self->render_not_found unless( $it->rows );
    my $data = $it->hash;

    my $images_it = $dbis->select( 'product_images', ['*'], { is_deleted => 0, products_id => $id }, { order_by => 'sortorder, id' } )
        or die $dbis->error;
    $self->stash( hash => $data, images => $images_it );
    $self->render;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

sub associate {
    my $self = shift;
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    my $now_used_it = $dbis->select( 'form_products', [ qw/id products_id/ ], { is_deleted => 0, forms_id => $self->stash('form_id') } )
        or die $dbis->error;
    my $used_ids = {};
    while( my $line = $now_used_it->hash ) {
        $used_ids->{ $line->{products_id} } = 1;
    }
    my $it = $dbis->select( 'products', [ '*' ], { is_deleted => 0 }, { order_by => 'sortorder, id' } )
        or die $dbis->error;

    $self->stash( datas => $it, used_ids => $used_ids );
    $self->render;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}


sub do_associate {
    my $self = shift;

    my $form_id = $self->stash('form_id');
    my $params = $self->req->params->to_hash;
#    $self->app->log->info( "params : " . Dumper( $params ) );


    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    
    $dbis->update( 'form_products',
                   { is_deleted => 1, date_deleted => 'now' },
                   { forms_id => $form_id } )
        or die $dbis->error;
    
    if( exists $params->{product_ids} ) {
        $params->{product_ids} = [ $params->{product_ids} ]
            unless( ref( $params->{product_ids} ) eq 'ARRAY' );
        
        foreach my $product_id ( @{ $params->{product_ids} } ) {
            
            my $it = $dbis->select('form_products', ['id'], { forms_id => $form_id, products_id => $product_id } )
                or die $dbis->error;
            if( $it->rows ) {
                $dbis->update( 'form_products',
                               { is_deleted => 0, date_updated => 'now', date_deleted => undef },
                               { id => $it->hash->{id} } )
                    or die $dbis->error;
            }
            else {
                $dbis->insert('form_products', { forms_id => $form_id, products_id => $product_id } )
                    or die $dbis->error;
            }
        }
    }
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    $self->redirect_to( $self->get_path( '/admin/forms/view/' . $form_id ) );
}

sub get_form_products {
    my $class   = shift;
    my $app     = shift;
    my $form_id = shift;

#    $app->log->debug( Dumper( $app->config->{dsn} ) );
    my $dbis = DBIx::Simple->new( @{ $app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    my $it = $dbis->query( "SELECT p.*, fp.sortorder AS fp_sortorder FROM products AS p, form_products AS fp WHERE p.is_deleted = FALSE AND fp.is_deleted = FALSE AND fp.products_id = p.id AND fp.forms_id = ? ORDER BY fp.sortorder, p.sortorder, p.id",
                           $form_id )
        or die $dbis->error;
    my $products = { hash => {}, list => [] };
    while( my $line = $it->hash ) {
        my $img_it = $dbis->select( 'product_images', [ '*' ], { products_id => $line->{id}, is_deleted => 0 }, { order_by => 'sortorder, id' } );
        my $images = { has_image => 0, has_thumb => 0, has_slides => 0, slides => [] };
        while( my $img_line = $img_it->hash ) {
#            $app->log->debug( Dumper( $img_line ) );
            $img_line->{name} = $img_line->{name} || '';
            $img_line->{description} = $img_line->{description} || '';
            if( $img_line->{is_thumbnail} ) {
                $images->{thumb} = $img_line;
                $images->{has_thumb} = 1;
                $images->{has_image} = 1;
            }
            else {
                push( @{ $images->{slides} }, $img_line );
                $images->{has_slides} = 1;
                $images->{has_image} = 1;
            }
        }
#        $products->{hash}->{ $line->{id} } = $line;
        $products->{hash}->{ $line->{id} } = { map { $_ => $line->{$_} } qw/id price sortorder p_sortorder name description/ };
        $products->{hash}->{ $line->{id} }->{name} = $line->{name} || '';
        $products->{hash}->{ $line->{id} }->{description} = $line->{description} || '';
#       $products->{hash}->{ $line->{id} }->{name} = b( $line->{name} )->decode->to_string;
#       $products->{hash}->{ $line->{id} }->{description} = b( $line->{description} )->decode->to_string;
        $products->{hash}->{ $line->{id} }->{images} = $images;
        $products->{hash}->{ $line->{id} }->{use_tag_in_description} = $line->{use_tag_in_description};
        push( @{ $products->{list} }, $products->{hash}->{ $line->{id} } );
    }
#    $app->log->debug( Data::Dumper->new( [ { products => $products } ] )->Sortkeys( 1 )->Dump );
    return $products;
}

1;
