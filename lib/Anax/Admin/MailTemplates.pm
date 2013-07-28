package Anax::Admin::MailTemplates;

use strict;
use warnings;
use Validator::Custom::Anax;

use Mojo::Base 'Mojolicious::Controller';

use Anax::Admin::Forms;

use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

my $vc = Validator::Custom::Anax->new;

sub input {
    my $self   = shift;
    my $params = $self->req->params->to_hash;
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    $dbis->query( "SET timezone TO 'Asia/Tokyo';" ) or die $dbis->error;

    if( my $id = $self->stash('id') ) {
        my $rslt = $dbis->select('mail_templates', ['*'], { id => $id, is_deleted => 0 } )
            or die $dbis->error;
        $self->render_not_found unless( $rslt->rows );
        $params = $rslt->hash;
    }
    $self->stash( fields => Anax::Admin::Forms->new( $self )->get_fields( $dbis, [ $params->{forms_id} ] )  );
    $self->stash( messages => {}, params => $params );
    $self->render;
    
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}

sub register {
    my $self = shift;
    my $id   = $self->stash('id');

    my $params = $self->req->params->to_hash;
    my $rule = [
                from     => [ [ 'not_blank', '必ず入力してください' ] ],
                to       => [ [ 'not_blank', '必ず入力してください' ] ],
                subject  => [ [ 'not_blank', '必ず入力してください' ] ],
                body     => [ [ 'not_blank', '必ず入力してください' ] ],
                forms_id => [ [ 'not_blank', '必ず入力してください' ],
                              [ 'integer', '半角数字で入力してください' ] ],
               ];
    my $vrslt = $vc->validate( $params, $rule );
    $self->app->log->debug( Dumper( { vrslt => $vrslt, is_ok => $vrslt->is_ok } ) );
    unless( $vrslt->is_ok ) {
        $self->stash( missing => 1 ) if( $vrslt->has_missing );
        $self->stash( messages => $vrslt->messages_to_hash )
            if( $vrslt->has_invalid );
        $self->app->log->debug( Dumper( $self->stash ) );
        $self->render( template => 'admin/mail_templates/input', params => $params );
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        my $hash = { from => $params->{from} || '',
                     to => $params->{to} || '',
                     cc => $params->{cc} || undef,
                     bcc => $params->{bcc} || undef,
                     subject => $params->{subject},
                     body => $params->{body},
                     forms_id => $params->{forms_id},
                   };
        if( defined $id and $id =~ /^\d+$/ ) {
            $hash->{date_updated} = 'now';
            $dbis->update( 'mail_templates', $hash, { id => $id } )
                or die $dbis->error;
        }
        else {
            $dbis->insert( 'mail_templates', $hash )
                or die $dbis->error;
        }
        $dbis->commit or die $dbis->error;
        $dbis->disconnect or die $dbis->error;
        $self->redirect_to( '/admin/forms/view/' . $params->{forms_id} );
    }
}

1;
