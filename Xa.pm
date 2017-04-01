package Xa;

# -----------------------------------------------------------------------------
use strict;
use warnings;
use Data::Printer;
use Scalar::Util qw/blessed/;
use Carp qw/confess/;
use vars qw/$VERSION/;
$VERSION   = '1.001';

# -----------------------------------------------------------------------------
sub import
{
    my ( $class, $name ) = @_;
    my $caller = caller;
    my $imported = $name || 'xa';
    no strict 'refs';
    *{"$caller\::$imported"} = \&xa;
}

# -----------------------------------------------------------------------------
sub _xe
{
    my $msg = shift;
    p @_;
    return confess $msg;
}

# -----------------------------------------------------------------------------
# Set undefined values in $rc from %defaults
# -----------------------------------------------------------------------------
sub _xh
{
    my ( $rc, $defaults ) = @_;
    $rc->{$_} //= $defaults->{$_} for keys %{$defaults};
    return %{$rc};
}

# -----------------------------------------------------------------------------
# Set undefined values in $rc from @defaults
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
# Extract values from @args without redefinition
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
    return () unless defined $self;

    if ( blessed $self ) {
        if ( defined $_[0] ) {
            if ( ref $_[0] eq 'HASH' ) {
                if ( exists $_[1] ) {
                    if ( ref $_[1] eq 'HASH' ) {
                        _xe( 'Only 2 arguments for $self allowed', @_ )
                            if exists $_[2];
                        return ( $self, _xh( $_[0], $_[1] ) );
                    }
                    my $arg = shift;
                    return ( $self, _xha( $arg, \@_ ) );
                }
            }
            _xe( 'Odd HASH elements passed with $self', @_ ) if @_ % 2;
            return ( $self, _xa( \@_ ) );
        }
    }
    else {

        unless ( ref $self eq 'HASH' ) {
            unshift @_, $self;
            _xe( 'Odd HASH elements passed', @_ ) if @_ % 2;
            return _xa( \@_ );
        }

        if ( exists $_[1] ) {
            if ( ref $_[1] eq 'HASH' ) {
                _xe( 'Only 2 arguments allowed', @_ ) if exists $_[2];
                return _xh( $_[0], $_[1] );
            }
            else {
                _xe( 'Odd HASH elements passed', @_ ) if @_ % 2;
                return _xha( $self, \@_ );
            }
        }
    }
    return wantarray ? ( $self, undef ) : $self;
}

# -----------------------------------------------------------------------------
1;

__END__

=head1 NAME

Xa - named function/method arguments extractor with default values.

=head1 VERSION

Version 1.001

=head1 SYNOPSIS

    use Xa;
    sub aaa 
    {
        my %arg = xa @_;
        OR
        my %arg = xa @_, default_a => 'a', default_b => 'b'; 
    }

    use Xa 'xxx';
    sub aaa 
    {
        my %arg = xxx @_;
        OR
        my %arg = xxx @_, default_a => 'a', default_b => 'b'; 
    }
    aaa( a => 1, b => 2 );
    
    use Xa;
    # for blessed method
    sub aaa 
    {
        my ( $self, %arg ) = xa @_;
    }
    $obj->aaa( a => 1, b => 2 );
   

=head1 DESCRIPTION


=head1 SUBROUTINES/METHODS

=over

=item xa( I<@_> [, defaults ] )

=back

=head1 BUGS AND LIMITATIONS

Unknown.

=head1 INCOMPATIBILITIES

Unknown.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2017 Vsevolod Lutovinov.

This program is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself. The full text of this license can be found in 
the LICENSE file included with this module.

=head1 AUTHOR

Contact the author at klopp@yandex.ru

=head1 SOURCE CODE

Source code and issues can be found here:
 <https://github.com/klopp/perl-modules>

