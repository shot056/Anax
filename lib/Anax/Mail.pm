package Anax::Mail;

BEGIN {
    $Return::Value::NO_CLUCK = 1;
};

use strict;
use warnings;

use base 'Class::Accessor::Fast';
use Email::Send;
use Email::Simple::Creator;
use Email::Address;
use Tenjin;
use Tenjin::Template;
use DBIx::Simple;
use SQL::Maker;

use Data::Dumper;
use Jcode::CP932;
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

sub sendmail {
    my $self    = shift;
    my $charset = shift;
    my $parts   = shift;
    my $key     = shift;

    $charset = 'utf8' unless ( grep( $charset eq $_, qw/utf8 iso_2022_jp/ ) );

    my %header = (
          From => $charset eq 'utf8' ? $parts->{from} : Jcode::CP932->new( $parts->{from} )->$charset,
          To => $charset eq 'utf8' ? $parts->{to} : Jcode::CP932->new( $parts->{to} )->$charset,
          'Content-Transfer-Encoding' => 'base64'
    );
    foreach my $type ( qw/from to cc bcc/ ) {
        next unless( exists $parts->{ $type } and defined $parts->{ $type } and length $parts->{ $type } );
        my @addrs = Email::Address->parse( $parts->{$type} );
        foreach my $addr ( @addrs ) {
            foreach my $cmd ( qw/phrase comment/ ) {
                if( defined $addr->$cmd and length( $addr->$cmd ) ) {
                    my $str = ( $charset eq 'utf8' ? $addr->$cmd : Jcode::CP932->new( $addr->$cmd )->$charset );
                    my $new_str = b( $str )->encode->b64_encode;
                    chomp( $new_str );
                    $addr->$cmd( sprintf( '=?%s?B?%s?=', ( $charset eq 'utf8' ? 'UTF-8' : 'ISO-2022-JP' ), $new_str ) );
                }
            }
        }
        $header{ ucfirst( $type ) } = join( ', ', map { "$_" } @addrs );
    }
    if ( $charset eq 'utf8' ) {
        $header{'Content-Type'} = 'text/plain; charset=UTF-8';
    }
    else {
        $header{'Content-Type'} = 'text/plain; charset=ISO-2022-JP';
    }
    $header{'X-AnaxWebForm-Key'} = $key if ( defined $key );
    
    {
        my @encoded_subjects;
        foreach my $splited_str ( Jcode::CP932->new( $charset eq 'utf8' ? $parts->{subject} : Jcode::CP932->new( $parts->{subject} )->$charset )->jfold(20) ) {
            my $str = b( $splited_str )->b64_encode;
            $str =~ s/\r\n/\n/g;
            $str =~ s/\r/\n/g;
            chomp($str);
            push( @encoded_subjects, $str );
        }
        $header{Subject} = join( "\n       ", map { sprintf( '=?%s?B?%s?=', ( $charset eq 'utf8' ? 'UTF-8' : 'ISO-2022-JP' ), $_ ) } @encoded_subjects );
        $header{Subject} =~ s/\r\n/\n/g;
        $header{Subject} =~ s/\r/\n/g;
        $header{Subject} =~ s/\n\n/\n/g;
    }
    $parts->{body} =~ s/\r\n/\n/g;
    $parts->{body} =~ s/\r/\n/g;

    my $bccs = delete $header{Bcc};
    
    my $mail_body = b( $charset eq 'utf8' ? $parts->{body} : Jcode::CP932->new( $parts->{body} )->$charset )->encode->b64_encode;
    
    my $email = Email::Simple->create(
        header => [ %header ],
        body   => $mail_body
    );
    $self->app->log->info( "\n" . $email->as_string );
    my $sender = Email::Send->new( {
        mailer      => 'SMTP::TLS',
        mailer_args => [
            Host     => 'smtp.gmail.com',
            Port     => 587,
            User     => $self->username,
            Password => $self->password
        ]
    } );
    $self->app->log->info( "+++++ Sending Email To: $parts->{to} Cc: $parts->{cc}" );
    $sender->send($email);

    if ( defined $bccs and length( $bccs ) ) {
        foreach my $bcc ( Email::Address->parse( $bccs ) ) {
            my %tmp_header = %header;
            delete $tmp_header{'To'};
            delete $tmp_header{'Cc'};
            $tmp_header{'Bcc'} = "$bcc";
            $self->app->log->info( "+++++ Sending Email Bcc: $bcc" );
            my $email_bcc = Email::Simple->create(
                header => [ %tmp_header ],
                body   => $mail_body
            );
            $sender->send( $email_bcc );
        }
    }
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
