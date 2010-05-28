
use strict;
use warnings;

use Module::Build 0.3601;

my %module_build_args = (
  'build_requires' => {
    'File::Find' => '0',
    'File::Temp' => '0',
    'Module::Build' => '0.3601',
    'Test::More' => '0',
    'Test::Tester' => '0'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Tests POD for invalid links',
  'dist_author' => [
    'Apocalypse <APOCAL@cpan.org>'
  ],
  'dist_name' => 'Test-Pod-LinkCheck',
  'dist_version' => '0.004',
  'license' => 'perl',
  'module_name' => 'Test::Pod::LinkCheck',
  'recommends' => {},
  'requires' => {
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
    'perl' => '5.008'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
