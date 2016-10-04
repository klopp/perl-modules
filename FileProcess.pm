package FileProcess;

# ------------------------------------------------------------------------------
use Modern::Perl;
use File::Temp qw/tempfile/;
use File::Copy qw/move/;
use Carp qw/croak/;

# ------------------------------------------------------------------------------
use Exporter qw/import/;
use vars qw/$VERSION/;
$VERSION = '1.001';
our @EXPORT_OK = qw/processFile/;

# ------------------------------------------------------------------------------
sub processFile {
    # --------------------------------------------------------------------------
    #
    # options:
    #   infile ("-" => stdin)
    #   outfile ("-" => stdout)
    #   callback( $in_handle, $in_name, $temp_handle, $temp_name, $out_name )
    #   bak 
    #   tempdir 
    #   template 
    #   suffix 
    # return undef (success) or error message
    # --------------------------------------------------------------------------
    my (%opt) = @_;

    return "infile parameter required"  unless $opt{'infile'};
    return "outfile parameter required" unless $opt{'outfile'};
    return "callback parameter required" unless $opt{'callback'};

    my ( $inh, $outh, $outt, $tempdir, $template, $suffix );

    $template = $opt{'template'} || __PACKAGE__.'_XXXX';
    $suffix   = $opt{'suffix'}   || '.$$$';

    $tempdir = $opt{'tempdir'};
    $tempdir = $ENV{'TEMP'} unless $tempdir;
    $tempdir = $ENV{'TMP'} unless $tempdir;
    $tempdir ||= '.';

    if ( $opt{'infile'} eq '-' ) {
        $inh = \*STDIN;
    }
    else {
        open $inh, '<:encoding(UTF-8)', $opt{'infile'}
            or return "Can not open \"$opt{'infile'}\": $!";
    }
    if ( $opt{'outfile'} eq '-' ) {
        $outh = \*STDOUT;
    }
    else {
        eval { ( $outh, $outt ) = tempfile( $template, DIR => $tempdir, SUFFIX => $suffix, UNLINK => 1); };
        return @! if @!;
    }

    my $rc = $opt{'callback'}->($inh, $opt{'infile'}, $outh, $outt, $opt{'outname'} );
    return $rc if $rc;

    close $inh if $opt{'infile'} ne '-';
    if ( $opt{'outfile'} ne '-' ) {
        close $outh;
        if ( -f $opt{'outfile'} && $opt{'bak'} ) {
            move( $opt{'outfile'}, $opt{'outfile'} . '.' . $opt{'bak'} )
                or return "Error creating backup file \"$opt{'outfile'}.$opt{'bak'}\": $!";

        }
        move( $outt, $opt{'outfile'} )
            or return "Error writing file \"$opt{'outfile'}.''.$opt{'bak'}\": $!";
    }
    return undef;
}

# ------------------------------------------------------------------------------
1;

__END__

=head1 NAME

FileProcess - Wrapper to file modification routines with optional backup and stdin/stdout handling.

=head1 VERSION

Version 1.001

=head1 SYNOPSIS

    use FileProcess qw/processFile/;

    sub ppp
    {
        my ( $in_handle, $in_name, $temp_handle, $temp_name, $out_name ) = @_;
        # do something, return undef (success) or error message
    }
    my $rc = processFile(
        'tempdir'  => '/tmp',                 
        'template' => 'tempfileXXXX',                 
        'suffix'   => '$$$',               # use temp file /tmp/tempfileXXXX.$$$                 
        'infile'   => '-',                 # read data from stdin 
        'outfile'  => '/tmp/result.file',  # output to stderr
        'bak'      => 'bak',               # make backup copy /tmp/result.file.bak 
        'callback' => \&ppp                # user function to process file
    );
    die "Error: $rc\n" if $rc;    

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2016 Vsevolod Lutovinov.

This program is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself. The full text of this license can be found in 
the LICENSE file included with this module.

=head1 AUTHOR

Contact the author at klopp@yandex.ru

=head1 SOURCE CODE

Source code and issues can be found here:
 <https://github.com/klopp/perl-modules>
