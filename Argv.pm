package Argv;

# ------------------------------------------------------------------------------
use strict;
use warnings;
use Exporter;
use base 'Exporter';

# ------------------------------------------------------------------------------
our $VERSION = '1.0';
our @EXPORT  = qw/argv/;

# ------------------------------------------------------------------------------
sub argv
{
    my $av = shift || \@ARGV;
    my ( $lastarg, %argv );

    foreach ( @{$av} )
    {
        my ( $arg ) = /^-(.+)$/;
        $arg ||= $_;
        
        $argv{$lastarg} = '-', undef $lastarg, next
            if $_ eq '-' && $lastarg;

        next if $_ eq '-' && !$lastarg;
        
        if( /^-/ )
        {
            $lastarg = $arg;
            $argv{$arg} = 1;
        }
        else
        {
            if( $lastarg )
            {
                $argv{$lastarg} = $_;
                undef $lastarg;
            }
            else
            {
                $argv{$arg} = 1;
            }
        }
    }
    return wantarray ? %argv : \%argv;
}

# ------------------------------------------------------------------------------
1;

__END__

=head1 NAME

Argv - very-very-very simple command line parser.

=head1 VERSION

Version 1.0

=head1 SYNOPSIS

    use Argv;

    my %argv = argv();
    # OR
    my %argv = argv( [ '-O', '/dev/null', '-o', '-' ] );
    # OR
    my $argv = argv();
    # OR
    my $argv = argv( [ '-O', '/dev/null', '-o', '-' ] );

=head1 DESCRIPTION

Parse @ARGV or given arrayref. Rules:

B<->        : produces NO action

B<-foo>     : $argv{'foo'} => 1

B<-foo ->   : $argv{'foo'} => '-'

B<foo>      : $argv{'foo'} => 1

B<-foo bar> : $argv{'foo'} => 'bar'

=head1 SUBROUTINES/METHODS

=over

=item argv( I<$arrayref> )

Parse given arrayref, or @ARGV if arrayref is empty. Return hash or hashref.

=back

=head1 BUGS AND LIMITATIONS

B<-foo -bar> produces B<$argv{foo}=1, $argv{bar}=1>, 
NOT B<$argv{foo}='-bar'>. 

=head1 LICENSE AND COPYRIGHT

Coyright (C) 2015 Vsevolod Lutovinov.

This program is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself. The full text of this license can be found in 
the LICENSE file included with this module.

=head1 AUTHOR

Contact the author at klopp@yandex.ru.

=head1 SOURCE CODE

Source code and issues can be found here:
 <https://github.com/klopp/perl-modules>
 

