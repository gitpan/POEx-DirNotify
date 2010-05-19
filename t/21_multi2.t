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
use Test::More ( tests => 8 );

POEx::DirNotify->spawn();
pass( "built DirNotify session" );
My::Test->spawn( alias=>'dnotify' );

poe->kernel->run;

pass( 'Sane shutdown' );

###############################################################
package My::Test;

use strict;
use warnings;


use Test::More;
use Cwd;
use IO::File;
use File::Spec;
use POE::Session::PlainCall;

sub DEBUG () { 0 }

sub spawn
{
    my( $package, %init ) = @_;
    POE::Session::PlainCall->create(
                    package   => $package,
                    ctor_args => [ \%init ],
                    states    => [ qw( _start _stop start notify1 notify2 ) ]
                );
}

sub new
{
    my( $package, $args ) = @_;
    my $self = bless { notify=>$args->{alias}, delay=>$args->{delay} }, $package;
    $self->{dir} = File::Spec->catdir( getcwd, "something" );
    mkdir $self->{dir};
    $self->{file1} = File::Spec->catfile( $self->{dir}, 0+$self );
    DEBUG and diag( $self->{file1} );
    unlink $self->{file1} if $self->{file1};
    return $self;
}

sub _start
{
    my( $self ) = @_;
    DEBUG and diag( "_start $self" );
    poe->kernel->post( $self->{notify},  monitor => { path  => $self->{dir}, 
                                                      event => 'notify1',
                                                      args  => $self->{dir}
                                                    } );
    poe->kernel->post( $self->{notify},  monitor => { path  => $self->{dir}, 
                                                      event => 'notify2',
                                                      args  => [ 42, $self->{dir} ]
                                                    } );
    $self->{delay} = poe->kernel->delay_set( start => 2 );

}

sub _stop
{
    my( $self ) = @_;
    DEBUG and diag( "_stop $self" );
    if( $self->{file1} ) {
        unlink $self->{file1};
    }
}

sub start
{
    my( $self ) = @_;
    pass( "start" );
    DEBUG and diag( $self->{file1} );
    delete $self->{delay};
    IO::File->new( ">$self->{file1}" ) or die "Unable to create $self->{file1}: $!";
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
    unlink $self->{file1};
}

sub notify2
{
    my( $self, $change, $N, $path ) = @_;
    return if $self->{delay};
    is( $N, 42, "Args passed" );
    is( $path, $self->{dir}, "Change in $self->{dir}" );
    is_deeply( $change, { op=>'change',
                          path=>$self->{dir} }, " ... details" );

    # poe->kernel->call( $self->{notify}, unmonitor => { path => $self->{dir} } );
    return;
}

