#!/usr/bin/perl

use 5.008008;
use ExtUtils::MakeMaker;

unless( $^O eq 'linux' ) {
    die "This module only works on Linux, with dnotify\n";
}


# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'POEx::DirNotify',
    VERSION_FROM      => 'lib/POEx/DirNotify.pm', # finds $VERSION
    LICENSE           => 'perl',
    PREREQ_PM         => {
            'POE'       => 1.284,
            'Digest::MurmurHash' => 0.11,
            'POE::Session::PlainCall' => 0.0201,
            'Storable'                => 2
        }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/POEx/DirNotify.pm', # retrieve abstract from module
       AUTHOR         => 'Philip Gwyn <gwyn -at- cpan.org>') : ()),
);
