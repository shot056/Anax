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
               }
);
