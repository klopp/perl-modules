package Xa;

# -----------------------------------------------------------------------------
use strict;
use warnings;
use Data::Printer;
use Scalar::Util qw/blessed/;
use Carp qw/confess cluck/;
use vars qw/$VERSION/;
$VERSION = '1.002';

# -----------------------------------------------------------------------------
my $params = {
    'name'   => 'xa',
    'errors' => 'stop',
};

# -----------------------------------------------------------------------------
sub import
{
    my ( $class, $args ) = ( shift, {} );
    $args = @_ == 1 ? shift : {@_} if @_;
    confess __PACKAGE__ . " can receive HASH or HASH reference only, but got:\n" . np($args)
        unless ref $args eq 'HASH';
    $params->{$_} = $args->{$_} for keys %{$args};
    confess "Invalid \"errors\" value (stop|warn|pass):\n" . np( $params->{errors} )
        if defined $params->{errors} && $params->{errors} !~ /^stop|warn|pass$/;
    confess 'No "name" value' unless defined $params->{name};
    my $caller = caller;
    no strict 'refs';
    *{"$caller\::$params->{name}"} = \&xa;
}

# -----------------------------------------------------------------------------
sub _xe
{
    my $msg = shift . ':';
    $msg .= ( @_ ? "\n" . np(@_) : '' );
    confess $msg if $params->{errors} eq 'stop';
    cluck $msg   if $params->{errors} eq 'warn';
    return;
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
# Check key type. Trigger error if type is invalid. 
# Set values from key if type is HASH
# -----------------------------------------------------------------------------
sub _set_value
{
    my ( $rc, $data, $i ) = @_;
    
    my $ref = ref $data->[$i];
    if ($ref) {
        if ( $ref eq 'HASH' ) {
            _xe('Arguments after HASH defaults are disabled') if exists $data->[$i+1];
            return _xh( $rc, $data->[$i] );
        }
        _xe("Key can not be $ref type");
    }
    _xe( 'Odd HASH elements passed') unless exists $data->[ $i + 1 ];
    $rc->{ $data->[$i] } //= $data->[ $i + 1 ];
    return;
}

# -----------------------------------------------------------------------------
# Set undefined values in $rc from @defaults
# -----------------------------------------------------------------------------
sub _xha
{
    my ( $rc, $defaults ) = @_;
    for ( my $i = 0; $i < @{$defaults}; $i += 2 ) {
        last if _set_value( $rc, $defaults, $i );
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
        last if _set_value( \%rc, $args, $i );
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
                if ( exists $_[1] ) {
                    if ( ref $_[1] eq 'HASH' ) {
                        _xe( 'Arguments after HASH defaults are disabled', @_ )
                            if exists $_[2];
                        return ( $self, _xh( $_[0], $_[1] ) );
                    }
                    my $arg = shift;
                    return ( $self, _xha( $arg, \@_ ) );
                }
            }
            return ( $self, _xa( \@_ ) );
        }
    }
    else {
        return () unless defined $self;

        unless ( ref $self eq 'HASH' ) {
            unshift @_, $self;
            return _xa( \@_ );
        }

        if ( exists $_[0] ) {
            if ( ref $_[0] eq 'HASH' ) {
                _xe( 'Arguments after HASH defaults are disabled', @_ ) if exists $_[1];
                return _xh( $self, $_[0] );
            }
            else {
                return _xha( $self, \@_ );
            }
        }
    }
    return %{$self};
}

# -----------------------------------------------------------------------------
1;

__END__

=head1 NAME

Xa - named function/method arguments extractor with default values.

=head1 VERSION

Version 1.002

=head1 SYNOPSIS

    use Xa;
    sub aaa 
    {
        my %arg = xa @_;
        OR
        my %arg = xa @_, default_a => 'a', default_b => 'b'; 
        OR
        my %arg = xa @_, $defaults; 
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

