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
use Test::More ( tests => 5 );

POEx::DirNotify->spawn( alias=>'notify' );
pass( "built DirNotify session" );
My::Test->spawn( alias=>'notify' );

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
    my $self = bless { notify=>$args->{alias} }, $package;
    $self->{dir} = File::Spec->catdir( getcwd, "something" );
    mkdir $self->{dir};
    $self->{file1} = File::Spec->catfile( $self->{dir}, 0+$self );
    # diag( $self->{file1} );
    unlink $self->{file1} if $self->{file1};
    return $self;
}

sub _start
{
    my( $self ) = @_;
    # diag( '_start' );
    poe->kernel->post( $self->{notify},  monitor => { path  => $self->{dir}, 
                                                      event => 'notify1',
                                                      args  => $self->{dir}
                                                    } );
    $self->{delay} = poe->kernel->delay_set( start => 2 );
}

sub _stop {
    my( $self ) = @_;
    # diag( '_stop' );
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
    # diag( $self->{file1} );
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
#    poe->kernel->call( $self->{notify}, monitor => { path => $self->{file1}, 
#                                                     events => 'notify2', 
#                                                     args => $self->{file1} } );
#    $self->{delay} = poe->kernel->delay_set( next => 2 );

}

sub next
{
    my( $self ) = @_;
    pass( "next" );
    delete $self->{delay};
    unlink $self->{file1};
}

sub notify2
{
    my( $self, $file ) = @_;
    return if $self->{delay};
    is( $file, $self->{file1}, "Changed $self->{file1}" );

}
