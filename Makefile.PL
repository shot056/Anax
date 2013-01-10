use ExtUtils::MakeMaker;

WriteMakefile(
  PREREQ_PM => {
                'Mojolicious' => '3.54',
                'DBIx::Simple' => '1.35',
                'SQL::Maker' => '1.07',
                'Tenjin' => '0.070001',
                'Validator::Custom' => '0.15',
                'DateTime' => '0.77',
                'DateTime::Format::Pg' => '0.16007',
                'DBD::Pg' => '2.19.3',
                'SQL::Abstract' => '1.73',
                'Starman' => '0.3003',
                'Mojolicious::Plugin::CSRFDefender' => '0.0.6',
                'Jcode::CP932' => '0.08',
                'Email::Send::SMTP::TLS' => '0.04',
                'Email::Simple' => '2.102',
                'Email::Valid' => '0.190',
                'Data::Visitor' => '0.28',
                'File::Find::Iterator' => '0.4'
               }
);
