use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
  AUTHOR       => 'John Kirk (johnkirk[at]dystanhays.com)',
  NAME         => 'Qtk::QuickTk',
  VERSION_FROM => 'QuickTk.pm', # finds $VERSION
  PREREQ_PM    => { 'Text::TreeFile' => '0', }
  );
