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
    {
        my $forms_rslt = $dbis->query( "SELECT id, name FROM forms WHERE is_deleted = FALSE ORDER BY id" )
            or die $dbis->error;
        my $values = [];
        my $labels = {};
        while( my $line = $forms_rslt->hash ) {
            $labels->{$line->{id}} = $line->{name};
            push( @{ $values }, $line->{id} );
        }
        $self->stash( forms => { values => $values, labels => $labels } );
    }
    my $stmt = SQL::Maker::Select->new;
    $stmt->{new_line} = ' ';
    $stmt->add_select( join( ', ', qw/a.id a.email a.date_created a.date_updated af.forms_id/,
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
    $stmt->add_order_by('a.date_created' => 'DESC' );
    
    # "SELECT a.id, a.email, a.date_created, a.date_updated, af.forms_id, af.date_created AS af_date_created, af.date_updated AS af_date_updated FROM applicants AS a, applicant_form AS af WHERE a.is_deleted = FALSE AND a.id=af.applicants_id ORDER BY date_created DESC;"
    $self->app->log->debug( "[SQL] " . $stmt->as_sql . "; ( " . join(", ", $stmt->bind ) . " ) " );
    my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind )
        or die $dbis->error;

    $self->render( template => 'admin/applicants/index', datas => $rslt );
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}

sub view {
    my $self = shift;

    my $id = $self->stash('id');
    my $form_id = $self->stash('form_id');
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;

    my $applicants_it = $dbis->select('applicants', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    return $self->render_not_found unless( $applicants_it->rows );
    my $applicant = $applicants_it->hash;

    my $forms_it = $dbis->select('forms', ['*'], { is_deleted => 0, id => $form_id } )
        or die $dbis->error;
    return $self->render_not_found unless( $forms_it->rows );
    my $form = $forms_it->hash;

    my $applicant_datas_it = $dbis->query("SELECT ad.id, ad.fields_id, f.type, ad.field_options_id, ad.text FROM applicant_data AS ad, fields AS f WHERE ad.applicants_id = ? AND ad.forms_id = ? AND ad.fields_id=f.id;", $id, $form_id )
        or die $dbis->error;
    my $datas = { products => {} };
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

    my $applicant_products_it = $dbis->query("SELECT afp.id, afp.number, p.id AS product_id, p.name, p.price, p.description FROM applicant_form_products AS afp, products AS p WHERE afp.is_deleted = FALSE AND p.is_deleted = FALSE AND afp.products_id=p.id AND afp.applicants_id=? AND afp.forms_id=?;", $id, $form_id )
        or die $dbis->error;
    
    my $form_setting = Anax::Admin::Forms->get_form_setting( $self->app, $form_id, 1 );

    $self->stash( hash => $applicant );
    $self->stash( datas => $datas );
    $self->stash( products => $applicant_products_it );
    $self->stash( form_setting => $form_setting );

    $self->app->log->debug( Dumper( $self->stash ) );
    $self->render;
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
}

1;
