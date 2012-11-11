package Anax::Mail;

use strict;
use warnings;

use base 'Class::Accessor::Fast';

use Email::Send;
use Email::Send::Gmail;
use Email::Simple::Creator;
use Tenjin;
use Tenjin::Template;
use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;
use Jcode::CP932;
use MIME::Base64;
use Mojo::ByteStream 'b';

sub new {
    my $pkg  = shift;
    my $app  = shift;
    
    my $self = bless( {}, $pkg );
    $self->mk_accessors(qw/app username password tenjin/);
    $self->app( $app );
    $self->username( $app->config->{gmail}->{username} );
    $self->password( $app->config->{gmail}->{password} );
    $self->tenjin( Tenjin->new );
    return $self;
}

sub send {
    my $self = shift;
    my $id   = shift;
    my $data = shift;

    my $tmpl = $self->load( $id );
    $self->app->log->debug( Dumper( { tmpl => $tmpl } ) );
    my $parts = $self->render( $id, $tmpl, $data );
    $self->app->log->debug( Dumper( { parts => $parts } ) );

    my $charset = $tmpl->{charset};
    $charset = 'utf8' unless( grep( $charset eq $_, qw/utf8 iso_2022_jp/ ) );
    
    my %header = ( From => Jcode::CP932->new( $parts->{from} )->$charset,
                   To   => Jcode::CP932->new( $parts->{to} )->$charset,
                   'Content-Transfer-Encoding' => '7bit' );
    if( $charset eq 'utf8' ) {
        $header{'Content-Type'} = 'text/plain; charset=UTF-8';
    }
    else {
        $header{'Content-Type'} = 'text/plain; charset=ISO-2022-JP';
    }
    # $header{'Cc'} = [ Jcode::CP932->new( $parts->{cc} )->$charset ]
    #     if( exists $parts->{cc} and defined $parts->{cc} and length( $parts->{cc} ) );
    # push( @{ $header{'Bcc'} }, Jcode::CP932->new( $parts->{bcc} )->$charset )
    #     if( exists $parts->{bcc} and defined $parts->{bcc} and length( $parts->{bcc} ) );
    
    {
        my @encoded_subjects;
        foreach my $splited_str ( Jcode::CP932->new( Jcode::CP932->new( $parts->{subject} )->$charset )->jfold( 20 ) ) {
            my $str = encode_base64( $splited_str );
            chomp( $str );
            push( @encoded_subjects, $str );
        }
        $header{Subject} = join("\n",
                                map { sprintf('=?%s?B?%s?=',
                                              ( $charset eq 'utf8' ? 'UTF-8' : 'ISO-2022-JP' ),
                                              $_ ) } @encoded_subjects );
    }
    $parts->{body} =~ s/\r\n/\n/g;
    $parts->{body} =~ s/\r/\n/g;
    
    my $email = Email::Simple->create(
        header => [ %header ],
        body => Jcode::CP932->new( $parts->{body} )->utf8
    );
#    $email->header_str_set( 'Cc' => Jcode::CP932->new( $parts->{cc} )->$charset )
#        if( exists $parts->{cc} and defined $parts->{cc} and length( $parts->{cc} ) );
#    $email->header_str_set( 'Bcc' => Jcode::CP932->new( $parts->{bcc} )->$charset )
#        if( exists $parts->{bcc} and defined $parts->{bcc} and length( $parts->{bcc} ) );
    
    my $sender = Email::Send->new(
        {   mailer      => 'Gmail',
            mailer_args => [
                username => $self->username,
                password => $self->password
            ]
        }
    );
    $self->app->log->debug( Dumper( { email => $email, sender => $sender } ) );
    $sender->send( $email );
    return 1;
}

sub render {
    my $self = shift;
    my $id   = shift;
    my $tmpl = shift;
    my $data = shift;

    my $ret = {};
    foreach my $key ( grep( $_ ne 'charset', keys( %{ $tmpl } ) ) ) {
        $ret->{$key} = $self->_render( "$id.$key", $tmpl->{$key}, $data );
    }
    return $ret;
}

sub _render {
    my $self = shift;
    my $name = shift;
    my $tmpl = shift;
    my $data = shift;
    
    my $tenjin_template = Tenjin::Template->new;
    $tenjin_template->convert( $tmpl, $name );
    return $tenjin_template->render( $data );
}

sub load {
    my $self = shift;
    my $id   = shift;


    my $dbis = DBIx::Simple->new( @{ $self->app->config->{dsn} } )
        or die DBIx::Simple->error;
    $dbis->abstract = SQL::Maker->new( driver => $dbis->dbh->{Driver}->{Name} );
    $dbis->begin_work or die $dbis->error;
    my $rslt = $dbis->select( 'mail_templates', ['*'], { is_deleted => 0, id => $id } )
        or die $dbis->error;
    return undef unless( $rslt->rows );
    my $hash = $rslt->hash;
    my $tmpl = { map { $_ => b( $hash->{$_} )->decode->to_string || '' } qw/from to cc bcc subject body charset/ };
    $dbis->commit or die $dbis->error;
    $dbis->disconnect or die $dbis->error;
    return $tmpl;
}

# sub save {
#     my $self = shift;
#     my $data = shift;
#
#     $dbis->begin_work or die $dbis->error;
#     $dbis->insert( 'mail_templates', { forms_id => $data->{forms_id},
#                                        to => $data->{to} || '',
#                                        cc => $data->{cc} || '',
#                                        bcc => $data->{bcc} || '',
#                                        subject => $data->{subject} || '',
#                                        body => $data->{body} || '' } )
#         or die $dbis->error;
#     my $id = $dbis->last_insert_id( undef, 'public', 'mail_templates', 'id' )
#         or die $dbis->error;
#     $dbis->commit or die $dbis->error;
#     return $id;
# }

1;
