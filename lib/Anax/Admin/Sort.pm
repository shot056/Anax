package Anax::Admin::Sort;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';

my $target_map = {
                  'form_products' => { a => 'products',
                                       b => 'forms' },
                  'form_fields' => { a => 'fields',
                                     b => 'forms' },
                  'product_images' => { s => 'product_images',
                                        l => 'products_id' },
                  'field_options'  => { s => 'field_options',
                                        l => 'fields_id' }
                 };
sub edit {
    my $self = shift;

    my $target = $self->stash('target');
    my $id     = $self->stash('id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;

    my $method = "_" . $target . "_load";
    my $stmt;
    if( $self->can( $method ) ) {
        $stmt = $self->$method( $dbis, $id );
    }
    elsif( exists $target_map->{ $target } ) {
        $stmt = $self->_common_load( $dbis, $target, $id );
    }
    if( $stmt ) {
        $self->app->log->debug( "[SQL] " . $stmt->as_sql . "; ( " . join( ", ", $stmt->bind ) . " )" );
        my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind ) or die $dbis->error;
        $self->stash( result => $rslt );
        $self->stash( from => $self->req->params->to_hash->{from} || '' );
        $self->render();
    }
    else {
        $self->render_not_found;
    }
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

sub do_edit {
    my $self = shift;

    my $target = $self->stash('target');
    my $id     = $self->stash('id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;

    my $result;
    my $method = "_" . $target . "_save";
    if( $self->can( $method ) ) {
        $result = $self->$method( $dbis, $id, $self->req->params->to_hash->{ids} || [] );
    }
    elsif( exists $target_map->{ $target } ) {
        $result = $self->_common_save( $dbis, $target, $id, $self->req->params->to_hash->{ids} || [] );
    }
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    if( $result ) {
        $self->redirect_to( $self->req->params->to_hash->{'from'} ? $self->req->params->to_hash->{'from'} : $self->get_path( '/admin' ) );
    }
    else {
        $self->render_not_found;
    }
}


sub _common_load {
    my $self   = shift;
    my $dbis   = shift;
    my $target = shift;
    my $id     = shift;
    

    my $stmt = SQL::Maker::Select->new;
    $stmt->{new_line} = ' ';

    if( exists $target_map->{ $target }->{s} ) {
        my $table = $target_map->{ $target }->{s};
        my $link_field = $target_map->{ $target }->{l};
        $stmt->add_select( join(', ', qw/id name/ ) );
        $stmt->add_from( $table );
        $stmt->add_where( is_deleted => 0 );
        $stmt->add_where( $link_field => $id );
        $stmt->add_order_by( sortorder => 'ASC' );
    }
    else {
        my $table_a = $target_map->{ $target }->{a};
        my $table_b = $target_map->{ $target }->{b};
        my $table_j = sprintf( '%s_%s', ( $table_b =~ /^(.+)s$/ ), $table_a );
        $stmt->add_select( join( ', ', qw/j.id a.name/,
                                 sprintf( "'/admin/%s/view/' || a.id AS link", $table_a ) ) );
        $stmt->add_join( [ $table_a, 'a' ] => { type => 'inner',
                                                table => $table_j,
                                                alias => 'j',
                                                condition => sprintf( 'a.id = j.%s_id', $table_a ) } );
        $stmt->add_where( 'a.is_deleted' => 0 );
        $stmt->add_where( 'j.is_deleted' => 0 );
        $stmt->add_where( sprintf( 'j.%s_id', $table_b ) => $id );
        $stmt->add_order_by( 'j.sortorder, a.sortorder, a.id' => 'ASC' );
    }
    return $stmt;
}

sub _common_save {
    my $self   = shift;
    my $dbis   = shift;
    my $target = shift;
    my $id     = shift;
    my $ids    = shift;

    $ids = [ $ids ] unless( ref( $ids ) eq 'ARRAY' );
    
    my $table;
    my $link_field;
    if( exists $target_map->{ $target }->{s} ) {
        $table = $target_map->{ $target }->{s};
        $link_field = $target_map->{ $target }->{l};
    }
    else {
        my $table_a = $target_map->{ $target }->{a};
        my $table_b = $target_map->{ $target }->{b};
        $table = sprintf( '%s_%s', ( $table_b =~ /^(.+)s$/ ), $table_a );
        $link_field = sprintf('%s_id', $table_b );
    }
    for( my $i = 0; $i < scalar @{ $ids }; $i ++ ) {
        $dbis->update( $table, { sortorder => $i + 1 }, { id => $ids->[ $i ], $link_field => $id } );
    }
    return 1;
}

1;
