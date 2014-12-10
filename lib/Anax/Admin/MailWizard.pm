package Anax::Admin::MailWizard;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';

use Validator::Custom::Anax;
use Anax::Admin::Applicants;
use Anax::Admin::Forms;
use Anax::Form;

use Parallel::ForkManager;
use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;

my $vc = Validator::Custom::Anax->new;

sub select_target {
    my $self = shift;

    my $params = $self->req->params->to_hash;
    $self->stash( params => $params );

    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    $dbis->query( "SET timezone TO 'Asia/Tokyo';" ) or die $dbis->error;
    
    $self->stash( forms => Anax::Admin::Applicants->new( $self )->get_forms( $dbis ) );
    $self->stash( messages => {} )
            unless( exists $self->stash->{messages} );
    
    my $stmt = Anax::Admin::Applicants->new( $self )->get_stmt( $self->app, $dbis, $params );
    my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind ) or die $dbis->error;
    my $applicants = [];
    my $applicants_data = {};
    while( my $line = $rslt->hash ) {
        push( @{ $applicants }, $line );
        $applicants_data->{ $line->{id} } = Anax::Admin::Applicants->new( $self )->get_applicant_data( $dbis, $line->{id}, $line->{forms_id} );
    }
    $self->stash( fields => Anax::Admin::Forms->new( $self )->get_fields( $dbis, [ keys( %{ { map { $_->{forms_id} => 1 } @{ $applicants } } } ) ] ) );
    $self->stash( applicants => $applicants );
    $self->stash( applicants_data => $applicants_data );
    #$self->app->log->debug( Dumper( $self->stash ) );
    $self->render( template => 'admin/mail_wizard/select', datas => $applicants );
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
}

sub template_input {
    my $self = shift;

    my $params = $self->req->params->to_hash;
    $params->{target_ids} = [ $params->{target_ids} ]
        if( defined $params->{target_ids} and ref( $params->{target_ids} ) ne 'ARRAY' );
    $self->stash( params => $params );

    my $rule = [ target_ids => [ [ 'not_blank', '必ず選択してください' ] ] ];
    my $vrslt = $vc->validate( $params, $rule );
    
#    $self->app->log->debug( Dumper( { vrslt => $vrslt, is_ok => $vrslt->is_ok } ) );
    unless( $vrslt->is_ok ) {
        $self->stash( missing => 1 ) if( $vrslt->has_missing );
        $self->stash( messages => $vrslt->messages_to_hash )
            if( $vrslt->has_invalid );
        #$self->app->log->debug( Dumper( $self->stash ) );
        $self->app->log->info( "====> jump to select_target" );
        $self->select_target;
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        $dbis->query( "SET timezone TO 'Asia/Tokyo';" ) or die $dbis->error;

        # SELECT forms_id FROM applicant_form WHERE applicants_id IN ( 1,2,3,4,5,6 ) GROUP BY forms_id;
        my $forms_it = $dbis->select( 'applicant_form', [ 'forms_id' ], { is_deleted => 0, applicants_id => { IN => $params->{target_ids} } }, { group_by => 'forms_id' } )
            or die $dbis->error;
        my $forms_id = [];
        while( my $fline = $forms_it->hash ) {
            push( @{ $forms_id }, $fline->{forms_id} );
        }
        my $fields = Anax::Admin::Forms->new( $self )->get_fields( $dbis, $forms_id );
        $self->stash( fields => $fields );
        $self->stash( messages => {} )
            unless( exists $self->stash->{messages} );
        
        $self->render( template => 'admin/mail_wizard/template' );
        $dbis->commit;
        $dbis->disconnect or die $dbis->error;
    }
}

sub confirm {
    my $self = shift;
    
    my $params = $self->req->params->to_hash;
    $params->{target_ids} = [ $params->{target_ids} ]
        if( defined $params->{target_ids} and ref( $params->{target_ids} ) ne 'ARRAY' );
    $self->stash( params => $params );
    
    my $rule = [
                from     => [ [ 'not_blank', '必ず入力してください' ] ],
                to       => [ [ 'not_blank', '必ず入力してください' ] ],
                subject  => [ [ 'not_blank', '必ず入力してください' ] ],
                body     => [ [ 'not_blank', '必ず入力してください' ] ],
               ];
    my $vrslt = $vc->validate( $params, $rule );
#    $self->app->log->debug( Dumper( { vrslt => $vrslt, is_ok => $vrslt->is_ok } ) );
    unless( $vrslt->is_ok ) {
        $self->stash( missing => 1 ) if( $vrslt->has_missing );
        $self->stash( messages => $vrslt->messages_to_hash )
            if( $vrslt->has_invalid );
        #$self->app->log->debug( Dumper( $self->stash ) );
        $self->app->log->info( "====> jump to template_input" );
        $self->template_input();
    }
    else {
        my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
            or die DBIx::Simple->error;
        $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
        $dbis->begin_work or die $dbis->error;
        $dbis->query( "SET timezone TO 'Asia/Tokyo';" ) or die $dbis->error;

        my $target_stmt = Anax::Admin::Applicants->new( $self )->get_stmt( $self->app, $dbis, { id => $params->{target_ids} } );
        my $target_rslt = $dbis->query( $target_stmt->as_sql, $target_stmt->bind ) or die $dbis->error;
        my $applicants = [];
        my $applicants_data = {};
        while( my $line = $target_rslt->hash ) {
            push( @{ $applicants }, $line );
            $applicants_data->{ $line->{id} } = Anax::Admin::Applicants->new( $self )->get_applicant_data( $dbis, $line->{id}, $line->{forms_id} );
        }
        $self->stash( applicants => $applicants );
        $self->stash( applicants_data => $applicants_data );
        $self->stash( forms => Anax::Admin::Applicants->new( $self )->get_forms( $dbis ) );
        $self->stash( fields => Anax::Admin::Forms->new( $self )->get_fields( $dbis, [ keys( %{ { map { $_->{forms_id} => 1 } @{ $applicants } } } ) ] ) );
        $self->render( template => 'admin/mail_wizard/confirm'  );
        $dbis->commit;
        $dbis->disconnect or die $dbis->error;
    }
}

sub send_mail {
    my $self = shift;
    
    my $params = $self->req->params->to_hash;
    
    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    $dbis->query( "SET timezone TO 'Asia/Tokyo';" ) or die $dbis->error;
    
    my $stmt = Anax::Admin::Applicants->new( $self )->get_stmt( $self->app, $dbis, { id => $params->{target_ids} } );
    my $rslt = $dbis->query( $stmt->as_sql, $stmt->bind ) or die $dbis->error;

    my $applicants = [];
    my $applicants_data = {};
    while( my $line = $rslt->hash ) {
        push( @{ $applicants }, $line );
        $applicants_data->{ $line->{id} } = Anax::Admin::Applicants->new( $self )->get_applicant_data( $dbis, $line->{id}, $line->{forms_id} );
    }
    #$self->app->log->debug( Dumper( $applicants_data ) );
    my $mail = Anax::Mail->new( $self->app );
    my $tmpl = { from => $params->{from},
                 to => $params->{to},
                 cc => $params->{cc},
                 bcc => $params->{bcc},
                 subject => $params->{subject},
                 body => $params->{body} };
    my $uid = time . '.' . $$;
    my $form_settings = {};
    my $mail_targets = [];
    my $used_mailaddr = {};
    foreach my $applicant ( @{ $applicants } ) {
        my $datas = { mail_from => $self->app->config->{gmail}->{username} };
        unless( exists $form_settings->{$applicant->{forms_id}} ) {
            $form_settings->{$applicant->{forms_id}} = Anax::Admin::Forms->new( $self )->get_form_setting( $self->app, $applicant->{forms_id}, 1, $dbis );
        }
        my $form_setting = $form_settings->{$applicant->{forms_id}};
        my $params = {};

        foreach my $field_id ( keys( %{ $applicants_data->{ $applicant->{id} } } ) ) {
            my $val = $applicants_data->{ $applicant->{id} }->{ $field_id };
            unless( ref( $val ) eq 'ARRAY' ) {
                $val = &{$self->app->renderer->helpers->{decode}}( $self, $val ) . "";
            }
            $params->{"field_" . $field_id} = $val;
        }
        $datas->{params} = $params;
        $datas->{values} = Anax::Form->new( $self )->replace_params2value( $form_setting, { hash => {} }, $params );
        #$self->app->log->debug( Dumper( $datas ) );

        no warnings;
        my $parts = $mail->render( $uid, $tmpl, $datas );
        use warnings;
        # $self->app->log->debug( Dumper( { tmpl => $tmpl, datas => $datas, parts => $parts } ) );
        unless( exists $used_mailaddr->{ $parts->{to} } ) {
            $used_mailaddr->{ $parts->{to} } = $applicant->{id};
            push( @{ $mail_targets }, $parts );
        }
    }
    $self->render( template => 'admin/mail_wizard/send' );
    $dbis->commit;
    $dbis->disconnect or die $dbis->error;
    # $self->app->log->debug( Dumper( $mail_targets ) );
    my $pm = Parallel::ForkManager->new( 3 );
    foreach my $data ( @{ $mail_targets } ) {
        my $pid = $pm->start and next;
        $mail->sendmail( 'utf8', $data );
        $pm->finish;
    }
    $pm->wait_all_children;
}

1;
