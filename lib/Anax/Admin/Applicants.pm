package Anax::Admin::Applicants;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';

use Anax::Admin::Forms;

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

sub index {
    my $self = shift;

    my $params = $self->req->params->to_hash;

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    $dbis->query( "SET timezone TO 'Asia/Tokyo';" ) or die $dbis->error;

    $self->stash( forms => $self->get_forms( $dbis ) );
    {
        my $products_rslt = $dbis->query( "SELECT * FROM products WHERE is_deleted = FALSE ORDER BY id" )
            or die $dbis->error;
        my $values = [];
        my $labels = {};
        my $datas  = {};
        while( my $line = $products_rslt->hash ) {
            push( @{ $values }, $line->{id} );
            $labels->{ $line->{id} } = $line->{name};
            $datas->{ $line->{id} } = $line;
        }
        $self->stash( products => { values => $values, labels => $labels, datas => $datas } );
    }
    
    my $stmt = $self->get_stmt( $self->app, $dbis, $params );
    my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind ) or die $dbis->error;
    {
        my $afp_stmt = SQL::Maker::Select->new;
        $afp_stmt->{new_line} = ' ';
        $afp_stmt->add_select( "products_id, SUM( number ) AS numbers" );
        $afp_stmt->add_from( "applicant_form_products" );
        $afp_stmt->add_where( "is_deleted" => 0 );
        $stmt->{select} = [];
        $stmt->{select_map} = {};
        $stmt->{select_map_reverse} = {};
        $stmt->add_select('a.id');
        my $stmt_sql = "( " . $stmt->as_sql . " )";
        $afp_stmt->add_where( "applicants_id" => { IN => \$stmt_sql } );
        $afp_stmt->add_group_by( "products_id" );
        $self->app->log->debug( "[SQL] " . $afp_stmt->as_sql . "; ( " . join(", ", $afp_stmt->bind, $stmt->bind ) . " )" );
        my $pn_rslt = $dbis->query( $afp_stmt->as_sql, $afp_stmt->bind, $stmt->bind )
            or die $dbis->error;
        my $product_numbers = {};
        while( my $line = $pn_rslt->hash ) {
            $product_numbers->{ $line->{products_id} } = $line->{numbers};
        }
        $self->stash( product_numbers => $product_numbers );
    }
    my $data = [];
    if( $rslt->rows ) {
        my $alldata = $rslt->hashes;
        my $fields_data = $self->get_field_data( $self->app, $dbis, [ map { { id => $_->{id}, forms_id => $_->{forms_id} } } @{ $alldata } ] );
        foreach my $line ( @{ $alldata } ) {
            $line->{fields} = $fields_data->{ $line->{id} . "_" . $line->{forms_id} } || {};
            push( @{ $data }, $line );
        }
    }
    my $fields = $self->get_fields( $dbis );
    my $field_options = $self->get_field_options( $dbis );
    $self->app->log->debug( Data::Dumper->new( [ { data => $data, fields => $fields, field_options => $field_options } ] )->Sortkeys( 1 )->Dump );
    $self->render( template => 'admin/applicants/index', datas => $data, fields => $fields, field_options => $field_options );
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}

sub get_fields {
    my $self = shift;
    my $dbis = shift;

    my $rslt = $dbis->select( 'fields', [ qw/id name type/ ],
                              { is_deleted => 0,
                                show_in_list => 1 },
                              { order_by => 'sortorder' } ) or die b( $dbis->error );
    return $rslt->hashes;
}

sub get_field_options {
    my $self = shift;
    my $dbis = shift;

    my $rslt = $dbis->query( "SELECT id, fields_id, name FROM field_options WHERE is_deleted = FALSE AND fields_id IN ( SELECT id FROM fields WHERE show_in_list = TRUE AND is_deleted = FALSE ) ORDER BY fields_id, sortorder;" ) or die b( $dbis->error );
    my %fos;
    while( my $line = $rslt->hash ) {
        $fos{ $line->{fields_id} } = {}
            unless( exists $fos{ $line->{fields_id} } );
        $fos{ $line->{fields_id} }->{ $line->{id} } = $line->{name};
    }
    return \%fos;
}

sub get_field_data {
    my $self = shift;
    my $app  = shift;
    my $dbis = shift;
    my $targets = shift;

    my %target_ids;
    my %forms_id;
    foreach my $line ( @{ $targets } ) {
        $target_ids{ $line->{id} } = 1;
        $forms_id{ $line->{forms_id} } = 1;
    }

    my $stmt = SQL::Maker::Select->new;
    $stmt->{new_line} = ' ';
    $stmt->add_select( join( ", ", qw/id applicants_id forms_id fields_id text field_options_id/ ) );
    $stmt->add_from( 'applicant_data' );
    $stmt->add_where( is_deleted => 0 );
    $stmt->add_where( forms_id => { IN => [ keys %forms_id ] } );
    $stmt->add_where( applicants_id => { IN => [ keys %target_ids ] } );
    
    my $tf_stmt = SQL::Maker::Select->new;
    $tf_stmt->{new_line} = ' ';
    $tf_stmt->add_select( 'id' );
    $tf_stmt->add_from( 'fields' );
    $tf_stmt->add_where( is_deleted => 0 );
    $tf_stmt->add_where( show_in_list => 1 );
    my $tf_sql = "( " . $tf_stmt->as_sql . " )";
#    my $tf_sql = "( SELECT id FROM fields WHERE is_deleted = FALSE AND show_in_list = TRUE )";
    $stmt->add_where( fields_id => { IN => \$tf_sql } );
    
    $self->app->log->debug( "[SQL] " . $stmt->as_sql . "; ( " . join( ', ', $stmt->bind, $tf_stmt->bind ) . " )" );
#    $self->app->log->debug( "[SQL] " . $stmt->as_sql . "; ( " . join( ', ', $stmt->bind ) . " )" );
    my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind, $tf_stmt->bind );
#    my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind );
#    my $rslt = $dbis->select( 'applicant_data', [ qw/id applicants_id forms_id fields_id text field_options_id/ ],
#                              { is_deleted => 0,
#                                forms_id => { IN => \@forms_id },
#                                applicants_id => { IN => \@target_ids }
#                            } ) or die b( $dbis->error );
    my %retval;
    while ( my $line = $rslt->hash ) {
        $retval{ $line->{applicants_id} . "_" . $line->{forms_id} } = {}
            unless( exists $retval{ $line->{applicants_id} . "_" . $line->{forms_id} } );
        
        if( defined $line->{field_options_id} and $line->{field_options_id} =~ /^\d+$/ ) {
            $retval{ $line->{applicants_id} . "_" . $line->{forms_id} }->{ $line->{fields_id} } = []
                unless( exists $retval{ $line->{applicants_id} . "_" . $line->{forms_id} }->{ $line->{fields_id} } );
            push( @{ $retval{ $line->{applicants_id} . "_" . $line->{forms_id} }->{ $line->{fields_id} } }, $line->{field_options_id} );
        }
        else {
            $retval{ $line->{applicants_id} . "_" . $line->{forms_id} }->{ $line->{fields_id} } = $line->{text}
        }
    }
    return \%retval;
}

sub get_forms {
    my $self = shift;
    my $dbis = shift;
    
    my $forms_rslt = $dbis->query( "SELECT * FROM forms WHERE is_deleted = FALSE ORDER BY id" )
        or die $dbis->error;
    my $values = [];
    my $labels = {};
    my $datas  = {};
    while( my $line = $forms_rslt->hash ) {
        $labels->{$line->{id}} = $line->{name};
        push( @{ $values }, $line->{id} );
        $datas->{ $line->{id} } = $line;
    }
    return { values => $values, labels => $labels, datas => $datas };
}
sub get_stmt {
    my $self = shift;
    my $app  = shift;
    my $dbis = shift;
    my $params = shift;
    
    my $stmt = SQL::Maker::Select->new;
    $stmt->{new_line} = ' ';
    $stmt->add_select( join( ', ', qw/a.id a.email a.date_created a.date_updated af.forms_id/,
                             'af.id AS af_id',
                             'af.date_created AS af_date_created',
                             'af.date_updated AS af_date_updated' ) );
    $stmt->add_join( [ 'applicants', 'a' ] => { type => 'inner',
                                                table => 'applicant_form',
                                                alias => 'af',
                                                condition => 'a.id = af.applicants_id' } );
    $stmt->add_where( 'a.is_deleted' => 0 );
    $stmt->add_where( 'af.is_deleted' => 0 );
    
    $stmt->add_where( 'af.forms_id' => $params->{forms_id} )
        if( exists $params->{forms_id} );
    $stmt->add_where( 'af.date_created' => { '>=' => $params->{date_created_from} } )
        if( exists $params->{date_created_from} and length( $params->{date_created_from} ) and $params->{date_created_from} =~ /^\d{4}-\d{1,2}-\d{1,2}$/ );
    $stmt->add_where( 'af.date_created' => { '<=' => $params->{date_created_to} } )
        if( exists $params->{date_created_to} and length( $params->{date_created_to} ) and $params->{date_created_to} =~ /^\d{4}-\d{1,2}-\d{1,2}$/ );
    $stmt->add_where( 'a.id' => { IN => [ grep( $_ =~ /^\d+$/, @{ $params->{id} } ) ] } )
        if( exists $params->{id} and ref( $params->{id} ) eq 'ARRAY' and scalar grep( $_ =~ /^\d+$/, @{ $params->{id} } ) );
    $stmt->add_order_by('a.date_created' => 'DESC' );
    
    # "SELECT a.id, a.email, a.date_created, a.date_updated, af.forms_id, af.date_created AS af_date_created, af.date_updated AS af_date_updated FROM applicants AS a, applicant_form AS af WHERE a.is_deleted = FALSE AND a.id=af.applicants_id ORDER BY date_created DESC;"
    $app->log->debug( "[SQL] " . $stmt->as_sql . "; ( " . join(", ", $stmt->bind ) . " )" );

    return $stmt;
}

sub view {
    my $self = shift;

    my $id = $self->stash('id');
    my $form_id = $self->stash('form_id');
    
    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;

    return $self->render_not_found
        unless( $self->load_view_data_to_stash( $dbis, $id, $form_id ) );
    $self->app->log->debug( Dumper( $self->stash ) );
    $self->render;
    
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

sub load_view_data_to_stash {
    my $self    = shift;
    my $dbis    = shift;
    my $id      = shift;
    my $form_id = shift;


    my $applicants_it = $dbis->select('applicants', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    return 0 unless( $applicants_it->rows );
    my $applicant = $applicants_it->hash;

    my $forms_it = $dbis->select('forms', ['*'], { is_deleted => 0, id => $form_id } )
        or die $dbis->error;
    return 0 unless( $forms_it->rows );
    my $form = $forms_it->hash;

    my $datas = $self->get_applicant_data( $dbis, $id, $form_id );
    $datas->{products} = {};
    my $applicant_products_it = $dbis->query("SELECT afp.id, afp.number, p.id AS product_id, p.name, p.price, p.description FROM applicant_form_products AS afp, products AS p WHERE afp.is_deleted = FALSE AND p.is_deleted = FALSE AND afp.products_id=p.id AND afp.applicants_id=? AND afp.forms_id=?;", $id, $form_id )
        or die $dbis->error;

    my $form_setting = Anax::Admin::Forms->new( $self )->get_form_setting( $self->app, $form_id, 1 );

    $self->stash( hash => $applicant );
    $self->stash( datas => $datas );
    $self->stash( products => $applicant_products_it );
    $self->stash( form_setting => $form_setting );

    return 1;
}

sub get_applicant_data {
    my $self    = shift;
    my $dbis    = shift;
    my $id      = shift;
    my $form_id = shift;
    
    my $applicant_datas_it = $dbis->query("SELECT ad.id, ad.fields_id, f.type, ad.field_options_id, ad.text FROM applicant_data AS ad, fields AS f WHERE ad.applicants_id = ? AND ad.forms_id = ? AND ad.fields_id=f.id;", $id, $form_id )
        or die $dbis->error;
    my $datas = {};
    while( my $line = $applicant_datas_it->hash ) {
        if( $line->{type} =~ /^text/ ) {
            $datas->{ $line->{fields_id} } = $line->{text};
        }
        else {
            unless( exists $datas->{ $line->{fields_id} } ) {
                $datas->{ $line->{fields_id} } = [ $line->{field_options_id} ];
            }
            else {
                push( @{ $datas->{ $line->{fields_id} } }, $line->{field_options_id} );
            }
        }
    }
    return $datas;
}


sub disable {
    my $self = shift;
    
    my $id = $self->stash('id');
    my $form_id = $self->stash('form_id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;
    
    return $self->render_not_found
        unless( $self->load_view_data_to_stash( $dbis, $id, $form_id ) );

    $self->render;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

sub do_disable {
    my $self = shift;

    my $id = $self->stash('id');
    my $form_id = $self->stash('form_id');

    my $dbis = $self->dbis;
    $dbis->begin_work or die $dbis->error;

    $dbis->update( 'applicant_data', { is_deleted => 1 }, { applicants_id => $id, forms_id => $form_id } ) or die $dbis->error;
    $dbis->update( 'applicant_form_products', { is_deleted => 1 }, { applicants_id => $id, forms_id => $form_id } ) or die $dbis->error;
    $dbis->update( 'applicant_form', { is_deleted => 1 }, { applicants_id => $id, forms_id => $form_id } ) or die $dbis->error;
    $dbis->update( 'applicants', { is_deleted => 1 }, { id => $id } ) or die $dbis->error;

    $self->redirect_to( $self->get_path( '/admin/applicants' ) );
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

1;
