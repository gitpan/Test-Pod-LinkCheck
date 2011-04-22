
use strict;
use warnings;

BEGIN { require 5.006; }

use ExtUtils::MakeMaker 6.31;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'Tests POD for invalid links',
  'AUTHOR' => 'Apocalypse <APOCAL@cpan.org>',
  'BUILD_REQUIRES' => {
    'File::Find' => '0',
    'File::Temp' => '0',
    'ExtUtils::MakeMaker' => '6.31',
    'Test::More' => '0.88',
    'Test::Tester' => '0'
  },
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.31'
  },
  'DISTNAME' => 'Test-Pod-LinkCheck',
  'EXE_FILES' => [],
  'LICENSE' => 'perl',
  'NAME' => 'Test::Pod::LinkCheck',
  'PREREQ_PM' => {
    'App::PodLinkCheck::ParseLinks' => '4',
    'App::PodLinkCheck::ParseSections' => '0',
    'Capture::Tiny' => '0',
    'Config' => '0',
    'Exporter' => '0',
    'File::Spec' => '0',
    'Moose' => '1.01',
    'Moose::Util::TypeConstraints' => '1.01',
    'Pod::Find' => '0',
    'Test::Builder' => '0.94',
    'Test::Pod' => '1.44',
    'parent' => '0'
  },
  'VERSION' => '0.007',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



