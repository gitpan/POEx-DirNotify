## $Id$
#####################################################################
package POEx::DirNotify;

use 5.008008;
use strict;
use warnings;

our $VERSION = '0.01_00';
$VERSION = eval $VERSION;  # see L<perlmodstyle>

use POE;
use POE::Session::PlainCall;

use Digest::MurmurHash qw( murmur_hash );
use Storable qw( dclone );
use POSIX qw( sigaction );
use Fcntl qw/F_NOTIFY O_RDONLY
            DN_CREATE DN_ACCESS DN_MODIFY DN_RENAME
            DN_DELETE DN_ATTRIB DN_MULTISHOT
           /;

sub DEBUG () { 0 }

#############################################
sub spawn
{
    my( $package, %init ) = @_;

    my $options = delete $init{options};
    $options ||= {};

    POE::Session::PlainCall->create(
                    package   => $package,
                    ctor_args => [ \%init ],
                    options   => $options,
                    states    => [ qw( _start _stop shutdown
                                       monitor unmonitor
                                       sig_notify
                                 ) ]
                );
    
}

#############################################
sub new
{
    my( $package, $args ) = @_;

    my $self = bless { 
                       path=>{}         # path => $notifies
                     }, $package;
    $self->{alias} = $args->{alias} || 'dnotify';
    return $self;
}


#############################################
sub _start
{
    my( $self ) = @_;
    poe->kernel->alias_set( $self->{alias} );
    poe->kernel->sig( IO => 'sig_notify' );
    poe->kernel->sig( shutdown => 'shutdown' );
}

#############################################
sub _stop
{
}


#############################################
sub sig_notify
{
    my( $self, $signame ) = @_;
    DEBUG and warn "Notify $signame";
    poe->kernel->sig_handled;
    foreach my $event ( $self->_find_changes ) {
        DEBUG and warn "Call @$event";
        poe->kernel->post( @$event );
    }
}

#############################################
sub _find_path
{
    my( $self, $path ) = @_;
    return $self->{path}{ $path };
}


sub _build_details
{
    my( $self, $path ) = @_;
    my @stat = stat $path;
    return 0 unless @stat;
    $stat[11] = 0;
    $stat[12] = 0;
    return murmur_hash( join '-', @stat );
}

#############################################
sub _find_changes
{
    my( $self ) = @_;
    my @ret;
    foreach my $notify ( values %{ $self->{path} } ) {
        my $details = $self->_build_details( $notify->{path} );
        my $op = 'change';
        $op = 'delete' unless $details;
        if( $details ne $notify->{details} ) {
            foreach my $event ( @{ $notify->{call} } ) {
                my $E = dclone $event;
                $E->[2] = { op=>$op, 
                            path=>$notify->{path} 
                          };
                push @ret, $E;
            }
        }
    }
    return @ret;
}

#############################################
sub monitor
{
    my( $self, $args ) = @_;
    my $path = $args->{path};
    my $caller = join ' ', at => poe->caller_file, 
                               line => poe->caller_line;

    my $flags = DN_MODIFY|DN_CREATE|DN_RENAME|DN_DELETE|DN_ATTRIB|DN_MULTISHOT; # XXX

    my $call = $self->_build_call( $args );

    my $notify = $self->_find_path( $path );
    if( $notify ) {
        DEBUG and warn "Monitor $path again\n";
        push @{ $notify->{call} }, $call;
        poe->kernel->refcount_increment( poe->sender, "NOTIFY $path" );
        return 1;
    }


    unless( -d $path ) {
        die "$path isn't a directory $caller\n";
    }

    DEBUG and warn "Monitor $path\n";

    my $details = $self->_build_details( $path );

    $notify = {
                path => $path,
                call => [ $call ],
                details => $details,
                fd   => undef,
            };

    $self->{path}{$path} = $notify;

    my $fd;
    sysopen( $fd, $path, O_RDONLY ) or die "sysopen $path: $! $caller\n";
    fcntl( $fd, F_NOTIFY, $flags ) or warn "fcntl F_NOTIFY: $!";

    $notify->{fd} = $fd;    
    poe->kernel->refcount_increment( poe->session->ID, "NOTIFY $path" );
    poe->kernel->refcount_increment( poe->sender, "NOTIFY $path" );

    return 1;
}

sub _build_call
{
    my( $self, $args ) = @_;
    my $event = $args->{event};
    my $A     = $args->{args};
    my $session = poe->sender;

    my $call = [ $session, $event, undef ];
    if( $A ) {
        $A = dclone $A if ref $A;
        if( 'ARRAY' eq ref $A ) {
            push @$call, @$A;
        }
        else {
            push @$call, $A;
        }
    }
    return $call;
}


#############################################
sub unmonitor
{
    my( $self, $args ) = @_;
    my $path = $args->{path};
    my $session = poe->sender;
    my $caller = join ' ', at => poe->caller_file, 
                               line => poe->caller_line;
    my $notify = $self->_find_path( $path );
    unless( $notify ) {
        warn "$path wasn't monitored $caller\n";
        return;
    }

    my @calls;
    foreach my $call ( @{ $notify->{call} } ) {
        if( $call->[0] eq $session ) {
            poe->kernel->refcount_decrement( $session, 
                                             "NOTIFY $notify->{path}" );
        }
        else {
            push @calls, $call;
        }
    }


    if( @calls ) {
        $notify->{call} = \@calls;
        DEBUG and warn "$path still being monitored\n";
        return;
    }
    DEBUG and warn "Unmonitor $path\n";

    fcntl( $notify->{fd}, F_NOTIFY, 0 ) or warn "fcntl F_NOTIFY: $! $caller\n";

    poe->kernel->refcount_decrement( poe->session->ID, "NOTIFY $notify->{path}" );
    delete $notify->{fd};
    delete $self->{path}{ $path };
    return;
}

#############################################
sub shutdown
{
    my( $self ) = @_;
    foreach my $path ( keys %{ $self->{path} } ) {
        poe->kernel->call( poe->session => 'unmonitor', { path=>$path } );
    }
}




1;
__END__

=head1 NAME

POEx::DirNotify - dnotify interface for POE

=head1 SYNOPSIS

    use strict;

    use POE;
    use POEx::DirNotify;

    POEx::DirNotify->new( alias=>'notify' );

    POE::Session->create(
        package_states => [ 
                'main' => [ qw(_start notification) ],
        ],
    );

    $poe_kernel->run();
    exit 0;

    sub _start {
        my( $kernel, $heap ) = @_[ KERNEL, HEAP ];

        $kernel->post( 'notify' => monitor => {
                path => '.',
                event => 'notification',
                args => [ $args ]
             } );
        return;
    }

    sub notification {
        my( $kernel, $hashref, $args ) = @_[ KERNEL, ARG0, ARG1];
        print "Something changed in $hashref->{path}\n";
        $kernel->post( notify => 'shutdown' );
        return;
    }

=head1 DESCRIPTION

POEx::DirNotify is a simple interface to the Linux file and directory change
notification interface, also called C<dnotify>.

It can monitor an existing directory for new files, deleted files, new
directories and more.  It can not detect the monitored directory being
deleted.  This is a limitation of the underlying dnotify.

=head1 METHODS

=head2 spawn

    POEx::Session->spawn( %options );

Takes a number of arguments, all of which are optional.

=over 4

=item alias

The session alias to register with the kernel.  Defaults to C<dnotify>.

=item options

A hashref of POE::Session options that are passed to the component's 
session creator.

=back


=head1 EVENTS

=head2 monitor

    $poe_kernel->call( dnotify => 'monitor', $arg );

Starts monitoring the specified path for the specified types of changes.

Accepts one argument, a hashref containing the following keys: 

=over 4

=item path

The filesystem path to the directory to be monitored.  Mandatory.

=item event

The name of the event handler in the current session to post changes back
to.  Mandatory.

=item args

An arrayref of arguments that will be passed to the event handler.

=back

=head2 unmonitor

    $poe_kernel->call( dnotify => 'unmonitor', $arg );

Ends monitoring of the specified path for the current session.

Accepts one argument, a hashref containing the following keys: 

=over 4

=item path

The filesystem path to the directory to be unmonitored.  Mandatory.

=back


=head2 shutdown

    $poe_kernel->call( dnotify => 'shutdown' );
    # OR
    $poe_kernel->signal( $poe_kernel => 'shutdown' );

Shuts down the component gracefully. All monitored paths will be closed. Has
no arguments.


=head1 SEE ALSO

L<POE>.

This module's API was heavily inspired by
L<POE::Component::Win32::ChangeNotify>.

=head1 AUTHOR

Philip Gwyn, E<lt>gwyn -at- cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Philip Gwyn.  All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
