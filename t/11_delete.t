#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    sub POE::Kernel::TRACE_SIGNALS () { 0 }
}

use Data::Dumper;
use POE;
use POEx::DirNotify;
use POE::Session::PlainCall;
use Test::More ( tests => 4 );

SKIP: {
    skip "We don't seem to get a notify on directory deletion", 4;
    
    POEx::DirNotify->spawn( alias=>'notify' );
    pass( "built DirNotify session" );
    My::Test->spawn( alias=>'notify' );

    poe->kernel->run;
    pass( 'Sane shutdown' );
}

###############################################################
package My::Test;

use strict;
use warnings;

use Test::More;
use Cwd;
use IO::File;
use File::Spec;
use POE::Session::PlainCall;

use File::Path qw( mkpath rmtree );

sub spawn
{
    my( $package, %init ) = @_;
    POE::Session::PlainCall->create(
                    package   => $package,
                    ctor_args => [ \%init ],
                    states    => [ qw( _start _stop start notify1 ) ]
                );
}

sub new
{
    my( $package, $args ) = @_;
    my $self = bless { notify=>$args->{alias} }, $package;
    $self->{dir} = File::Spec->catdir( getcwd, "something" );
    rmtree( [ $self->{dir} ] );
    mkpath( [ $self->{dir} ], 0, 0700 );
    return $self;
}

sub _start
{
    my( $self ) = @_;
    diag( '_start' );
    poe->kernel->post( $self->{notify},  monitor => { path  => $self->{dir}, 
                                                      event => 'notify1',
                                                      args  => $self->{dir}
                                                    } );
    $self->{delay} = poe->kernel->delay_set( start => 2 );
}

sub _stop {
    my( $self ) = @_;
    diag( '_stop' );
    if( $self->{file1} ) {
        unlink $self->{file1};
    }
    if( $self->{dir} ) {
        rmdir $self->{dir};
    }
}

sub start
{
    my( $self ) = @_;
    pass( "start" );
    # diag( $self->{dir} );
    delete $self->{delay};
    rmtree( $self->{dir} ) or die "Unable to remove $self->{dir}: $!";
    return;
}

sub notify1
{
    my( $self, $change, $path ) = @_;
    return if $self->{delay};
    is( $path, $self->{dir}, "Change in $self->{dir}" );
    is_deeply( $change, { op=>'change',
                          path=>$self->{dir} }, " ... details" );

    poe->kernel->call( $self->{notify}, unmonitor => { path => $self->{dir} } );
}
