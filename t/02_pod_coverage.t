#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage 1.00 required for testing POD coverage" if $@;

plan tests => 1;
pod_coverage_ok(
        "POEx::DirNotify",
        { also_private => [ qw( DEBUG new sig_notify ) ],
        },
        "POEx::DirNotify, ignoring private functions",
);

