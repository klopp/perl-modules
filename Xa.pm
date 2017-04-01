package Xa;

use strict;
use warnings;
use Data::Printer;
use Scalar::Util qw/blessed/;
use Carp qw/confess/;

# -----------------------------------------------------------------------------
sub import 
{
    my $caller = caller;
    no strict 'refs';
    *{"$caller\::xa"} = \&xa;
}
 
# -----------------------------------------------------------------------------
sub _xe
{
    my $msg = shift;
    p @_;
    return confess $msg;
}

# -----------------------------------------------------------------------------
sub _xh
{
    my ( $rc, $defaults ) = @_;
    $rc->{$_} //= $defaults->{$_} for keys %{$defaults};
    return %{$rc};
}

# -----------------------------------------------------------------------------
sub _xha
{
    my ( $rc, $defaults ) = @_;
    for ( my $i = 0; $i < @{$defaults}; $i += 2 ) {
        $rc->{ $defaults->[$i] } //= $defaults->[ $i + 1 ];
    }
    return %{$rc};
}

# -----------------------------------------------------------------------------
sub _xa
{
    my ($args) = @_;
    my %rc;

    for ( my $i = 0; $i < @{$args}; $i += 2 ) {
        $rc{ $args->[$i] } //= $args->[ $i + 1 ];
    }
    return %rc;
}

# -----------------------------------------------------------------------------
sub xa
{
    my $self = shift;

    if ( defined $self && blessed $self ) {
        if ( defined $_[0] ) {
            if ( ref $_[0] eq 'HASH' ) {
                if ( defined $_[1] ) {
                    if ( ref $_[1] eq 'HASH' ) {
                        _xe( 'Only 2 arguments for $self allowed!', \@_ )
                            if defined $_[2];
                        return ( $self, _xh( $_[0], $_[1] ) );
                    }
                    my $arg = shift;
                    return ( $self, _xha( $arg, \@_ ) );
                }
            }
            _xe( 'Odd HASH elements passed with $self!', \@_ ) if @_ % 2;
            return ( $self, _xa( \@_ ) );
        }
    }
    else {
        return () unless defined $self;

        unless ( ref $self eq 'HASH' ) {
            unshift @_, $self;
            _xe( 'Odd HASH elements passed!', \@_ ) if @_ % 2;
            return _xa( \@_ );
        }

        if ( defined $_[1] ) {
            if ( ref $_[1] eq 'HASH' ) {
                _xe( 'Only 2 arguments allowed!', \@_ ) if defined $_[2];
                return _xh( $_[0], $_[1] );
            }
            else {
                _xe( 'Odd HASH elements passed!', \@_ ) if @_ % 2;
                return _xha( $self, \@_ );
            }
        }
    }
    return wantarray ? ( $self, undef ) : $self;
}

# -----------------------------------------------------------------------------
# That's All, Folks!
# -----------------------------------------------------------------------------
1;

