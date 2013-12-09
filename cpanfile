on 'configure' => sub {
    requires 'Module::Install';
    requires 'Module::Install::CPANfile';
};

requires 'Mojolicious', '== 4.58';
requires 'DBIx::Simple', '== 1.35';
requires 'SQL::Maker', '== 1.12';
requires 'Tenjin', '== 0.070001';
requires 'Validator::Custom', '== 0.22';
requires 'DateTime', '== 1.03';
requires 'DateTime::Format::Pg', '== 0.16009';
requires 'DBD::Pg', '== 2.19.3';
requires 'SQL::Abstract', '== 1.74';
requires 'Starman', '== 0.4008';
requires 'Mojolicious::Plugin::CSRFDefender', '== 0.0.8';
requires 'Jcode::CP932', '== 0.08';
requires 'Email::Send::SMTP::TLS', '== 0.04';
requires 'Email::Simple', '== 2.202';
requires 'Email::Valid', '== 1.192';
requires 'Data::Visitor', '== 0.30';
requires 'File::Find::Iterator', '== 0.4';
requires 'Parallel::ForkManager', '== 1.05';
requires 'Email::Address', '== 1.900';
