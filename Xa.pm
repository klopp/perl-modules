package Xa;

# -----------------------------------------------------------------------------
use strict;
use warnings;
use Readonly;
use Data::Printer;
use Scalar::Util qw/blessed dualvar/;
use Carp qw/confess cluck/;
use vars qw/$VERSION/;
$VERSION = '1.005';
Readonly::Scalar my $AP => qr/\A[^\W\d]\w*\z/;
Readonly::Hash my %EP => map { $_ => 1 } qw/stop warn pass quiet/;

# -----------------------------------------------------------------------------
my $p = {
    alias              => 'xa',
    errors             => 'stop',
    defaults_for_undef => undef,
    replace_undef      => dualvar( 0, '' ),
};

# -----------------------------------------------------------------------------
sub import
{
    my ( $class, $args ) = ( shift, {} );
    $args = @_ == 1 ? shift : {@_} if @_;

    confess __PACKAGE__ . ' can receive HASH or HASH reference only, but got: ' . np($args)
        unless ref $args eq 'HASH';
    $p->{$_} = $args->{$_} for keys %{$args};
    confess 'Wrong "errors" value (' . join( q{|}, keys %EP ) . q{):} . np( $p->{errors} )
        if defined $p->{errors} && !exists $EP{ $p->{errors} };
    confess 'No "alias" value' unless defined $p->{alias};
    confess "Wrong \"alias\" value $AP: " . np( $p->{alias} )
        unless $p->{alias} =~ $AP;
    my $caller = caller;
    no strict 'refs';
    *{"$caller::$p->{alias}"} = \&xa;
}

# -----------------------------------------------------------------------------
sub _xa_error
{
    my $msg = shift . q{:};
    $msg .= ( @_ ? "\n" . np(@_) : q{} );
    confess $msg if $p->{errors} eq 'stop';
    cluck $msg   if $p->{errors} eq 'warn';
    return;
}

# -----------------------------------------------------------------------------
# Check result kesy if configured
# -----------------------------------------------------------------------------
sub _xa_check_keys
{
    my ($rc) = @_;
    for ( keys %{$rc} ) {
        my $ref = ref $_;
        $rc->{$_} = _xa_error("Key can not be $ref type") if $ref;
    }
}

# -----------------------------------------------------------------------------
# Set unexisting values in $rc from %defaults
# -----------------------------------------------------------------------------
sub _xa_defaults_from_hash
{
    my ( $rc, $defaults ) = @_;

    for ( keys %{$defaults} ) {
        next if !$p->{defaults_for_undef} && exists $rc->{$_};
        next if $p->{defaults_for_undef}  && defined $rc->{$_};
        my $ref = ref $defaults->{$_};
        _xa_error("Defaults key can not be '$ref' type") if $ref;
        $rc->{$_} = $defaults->{$_};
    }
    return _xa_finalize_data($rc);
}

# -----------------------------------------------------------------------------
sub _xa_finalize_data
{
    my ($rc) = @_;

    if ( $p->{replace_undef} ) {
        for ( keys %{$rc} ) {
            $rc->{$_} = $p->{replace_undef} unless defined $rc->{$_};
        }
    }
    return %{$rc};
}

# -----------------------------------------------------------------------------
# Check key type. Show error if type is invalid.
# Set values from key if type is HASH.
# -----------------------------------------------------------------------------
sub _xa_set_value_from_array
{
    my ( $rc, $data, $i ) = @_;

    return if exists $rc->{ $data->[$i] };

    my $ref = ref $data->[$i];
    if ($ref) {
        if ( $ref eq 'HASH' ) {
            _xa_error('Arguments after HASH defaults are disabled')
                if exists $data->[ $i + 1 ];
            return _xa_defaults_from_hash( $rc, $data->[$i] );
        }
        _xa_error("Key can not be '$ref' type");
    }
    _xa_error('Odd HASH elements passed') unless exists $data->[ $i + 1 ];
    $rc->{ $data->[$i] } = $data->[ $i + 1 ];
    return;
}

# -----------------------------------------------------------------------------
# Set unexisting values in $rc from @defaults
# -----------------------------------------------------------------------------
sub _xa_defaults_from_array
{
    my ( $rc, $defaults ) = @_;

    for ( my $i = 0; $i < @{$defaults}; $i += 2 ) {
        last if defined _xa_set_value_from_array( $rc, $defaults, $i );
    }
    return _xa_finalize_data($rc);
}

# -----------------------------------------------------------------------------
# Extract values from @args
# -----------------------------------------------------------------------------
sub _xa_data_from_array
{
    my ($args) = @_;
    my %rc;

    for ( my $i = 0; $i < @{$args}; $i += 2 ) {
        last if defined _xa_set_value_from_array( \%rc, $args, $i );
    }
    return _xa_finalize_data( \%rc );
}

# -----------------------------------------------------------------------------
sub xa
{
    my $self = shift;

    if ( defined $self && blessed $self ) {

        my ( $pkg, $isa ) = ( (caller)[0], ref $self );
        if ( $pkg ne $isa ) {
            $p->{errors} = 'stop';
            _xa_error( "Method of package '$pkg' called for invalid object type '$isa'",
                ( $self, @_ ) );
        }

        if ( defined $_[0] ) {
            if ( ref $_[0] eq 'HASH' ) {
                if ( exists $_[1] ) {
                    if ( ref $_[1] eq 'HASH' ) {
                        _xa_error( 'Arguments after HASH defaults are disabled', ( $self, @_ ) )
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

        if ( ref $self ne 'HASH' ) {
            unshift @_, $self;
            return _xa_data_from_array( \@_ );
        }

        if ( exists $_[0] ) {
            if ( ref $_[0] eq 'HASH' ) {
                _xa_error( 'Arguments after HASH defaults are disabled', ( $self, @_ ) )
                    if exists $_[1];
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

Version 1.005

=head1 SYNOPSIS

    use Xa;
    sub foo 
    {
        my %arg = xa @_;
        OR
        my %arg = xa @_, default_a => 'a', default_b => 'b'; 
        OR
        my %arg = xa @_, $defaults_hash_or_array_ref; 
    }
    foo( a => 1, b => 2 );
    foo( $hash_ref, default_c => 3 );
    
    use Xa alias => 'xxx';
    sub bar
    {
        my ( $self, %arg ) = xxx @_;
    }
    $foo->bar( a => 1, b => 2 );
   

=head1 DESCRIPTION

WIP

=head1 SUBROUTINES/METHODS

=over

=item xa( I<arguments> [, I<defaults> ] )

=back

=head1 CUSTOMIZATION

    use Xa 
        # export 'my_extract_arguments' function instead 'xa':
        alias     =>  'my_extract_arguments',  
        # errors handling (stop|warn|pass|quiet, quiet == pass):
        errors    => 'stop'
        # apply defaults to undefined values, default NO (undef):
        defaults_for_undef => 1,
        # replace undefined values to, default: dualvar(0,''):
        replace_undef    => undef

=head1 DIAGNOSTICS

=head2 Import diagnostics

=over

=item MODULE can receive HASH or HASH reference only, but got: ...

=item Wrong "errors" value (stop|warn|pass|quiet): ...

=item No "alias" value

=item Wrong "alias" value ...

=back

=head2 Runtime diagnostics

=over

=item Method of package 'FOO' called for invalid object type 'BAR'

=item Arguments after HASH defaults are disabled

=item Key can not be 'FOO' type

=item Defaults key can not be 'FOO' type

=item Odd HASH elements passed

=back

=head1 DEPENDENCIES

Readonly, Data::Printer, Scalar::Util, Carp  

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

