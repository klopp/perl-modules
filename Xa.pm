package Xa;

# -----------------------------------------------------------------------------
use strict;
use warnings;
use Data::Printer;
use Scalar::Util qw/blessed/;
use Carp qw/confess cluck/;
use vars qw/$VERSION/;
$VERSION = '1.003';

use Readonly;
Readonly::Scalar my $AP => qr/\A[^\W0-9]\w*\z/;
Readonly::Scalar my $EP => qr/\A(stop|warn|pass|quiet)\z/;

# -----------------------------------------------------------------------------
my $p = {
    alias  => 'xa',
    errors => 'stop',
};

# -----------------------------------------------------------------------------
sub import
{
    my ( $class, $args ) = ( shift, {} );
    $args = @_ == 1 ? shift : {@_} if @_;

    confess __PACKAGE__ . " can receive HASH or HASH reference only, but got:\n" . np($args)
        unless ref $args eq 'HASH';
    $p->{$_} = $args->{$_} for keys %{$args};
    confess "Wrong \"errors\" value $EP:\n" . np( $p->{errors} )
        if defined $p->{errors} && $p->{errors} !~ $EP;
    confess 'No "alias" value' unless defined $p->{alias};
    confess "Wrong \"alias\" value $AP\n" . np( $p->{alias} ) unless $p->{alias} =~ $AP;
    my $caller = caller;
    no strict 'refs';
    *{"$caller\::$p->{alias}"} = \&xa;
}

# -----------------------------------------------------------------------------
sub _xa_error
{
    my $msg = shift . ':';
    $msg .= ( @_ ? "\n" . np(@_) : '' );
    confess $msg if $p->{errors} eq 'stop';
    cluck $msg   if $p->{errors} eq 'warn';
    return;
}

# -----------------------------------------------------------------------------
# Set undefined values in $rc from %defaults
# -----------------------------------------------------------------------------
sub _xa_defaults_from_hash
{
    my ( $rc, $defaults ) = @_;
    for ( keys %{$defaults} ) {
        next if exists $rc->{$_};
        my $ref = ref $defaults->{$_};
        _xa_error("Key can not be $ref type") if $ref;
        $rc->{$_} = $defaults->{$_};
    }
    return %{$rc};
}

# -----------------------------------------------------------------------------
# Check key type. Show error if type is invalid.
# Set values from key if type is HASH.
# -----------------------------------------------------------------------------
sub _xa_set_value
{
    my ( $rc, $data, $i ) = @_;

    return if exists $rc->{ $data->[$i] };

    my $ref = ref $data->[$i];
    if ($ref) {
        if ( $ref eq 'HASH' ) {
            _xa_error('Arguments after HASH defaults are disabled') if exists $data->[ $i + 1 ];
            return _xa_defaults_from_hash( $rc, $data->[$i] );
        }
        _xa_error("Key can not be $ref type");
    }
    _xa_error('Odd HASH elements passed') unless exists $data->[ $i + 1 ];
    $rc->{ $data->[$i] } = $data->[ $i + 1 ];
    return;
}

# -----------------------------------------------------------------------------
# Set undefined values in $rc from @defaults
# -----------------------------------------------------------------------------
sub _xa_defaults_from_array
{
    my ( $rc, $defaults ) = @_;
    for ( my $i = 0; $i < @{$defaults}; $i += 2 ) {
        last if defined _xa_set_value( $rc, $defaults, $i );
    }
    return %{$rc};
}

# -----------------------------------------------------------------------------
# Extract values from @args without redefinition
# -----------------------------------------------------------------------------
sub _xa_data_from_array
{
    my ($args) = @_;
    my %rc;

    for ( my $i = 0; $i < @{$args}; $i += 2 ) {
        last if defined _xa_set_value( \%rc, $args, $i );
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
                        _xa_error( 'Arguments after HASH defaults are disabled', @_ )
                            if exists $_[2];
                        return ( $self, _xa_defaults_from_hash( $_[0], $_[1] ) );
                    }
                    my $arg = shift;
                    return ( $self, _xa_defaults_from_array( $arg, \@_ ) );
                }
            }
            return ( $self, _xa_data_from_array( \@_ ) );
        }
    }
    else {
        return () unless defined $self;

        unless ( ref $self eq 'HASH' ) {
            unshift @_, $self;
            return _xa_data_from_array( \@_ );
        }

        if ( exists $_[0] ) {
            if ( ref $_[0] eq 'HASH' ) {
                _xa_error( 'Arguments after HASH defaults are disabled', @_ ) if exists $_[1];
                return _xa_defaults_from_hash( $self, $_[0] );
            }
        }
    }
    return _xa_defaults_from_array( $self, \@_ );
}

# -----------------------------------------------------------------------------
1;

__END__

=head1 NAME

Xa - named function/method arguments extractor with default values.

=head1 VERSION

Version 1.003

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

=head1 CUSTOMIZATION

    use Xa 
        # export 'my_extract_arguments' function instead 'xa':
        alias =>  'my_extract_arguments',  
        # errors handling ('quiet' == 'pass'):
        errors => (stop|warn|pass|quiet)

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

