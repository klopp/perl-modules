package ConfigParse;

# ------------------------------------------------------------------------------
use Modern::Perl;
use English qw/-no_match_vars/;

use Data::Printer;

# ------------------------------------------------------------------------------
use Exporter;
use base qw/Exporter/;
use vars qw/$VERSION $error @EXPORT_OK/;
$VERSION   = '1.003';
@EXPORT_OK = qw/parse_config_file parse_config_data/;
use constant DEF_SECTION => q{_};

# ------------------------------------------------------------------------------
sub _parse_value {
	my ($val, $replaces) = @_;

	$val =~ s/^"|"$//gs;

	while( $val =~ /(\@([^\@]+)\@)/sm )
	{
		my $replace = $replaces->{$2} || q{};
		$val =~ s/$1/$replace/sm;
	}

	while( $val =~ /(%([^%]+)%)/sm )
	{
		my $replace = $ENV{$2} || q{};
		$val =~ s/$1/$replace/sm;
	}

	return $val;
}

# ------------------------------------------------------------------------------
sub _parse {
	my ($lines, $opt, $ini, $replaces) = @_;

	my $current;
	my $section = DEF_SECTION;
	my $lineno  = 0;
	my $line;
	my %multikey = map { $_ => 1 } @{ $opt->{'multikey'} };

	$error = undef;
	my $cmt = 0;

	while (defined($current = shift @{$lines})) {
		$lineno++;
		$current =~ s/^\s+|\s+$//gs;

		next if !$current || $current =~ /^[;#]/;

		if ($current eq q{/*}) {
			$cmt++;
			next;
		}
		if ($current eq q{*/}) {
			$cmt--;
			if ($cmt < 0) {
				$error = "Invalid line number $lineno: $current";
				return;
			}
			next;
		}
		next if $cmt;
		$line = $current;

		if ($current =~ /^\s*([^<]+?)\s*<<+\s*(\w+;)\s*$/s) {
			my $here = $2;
			$current = $1 . ' = ';
			my $newline = q{};

			while ($line ne $here) {
				$current .= $newline . "\n";
				$newline = shift @{$lines};
				last unless defined $newline;
				$lineno++;
				$line = $newline;
				$line =~ s/^\s+|\s+$//gs;
			}
		}

		while ($current =~ /\\$/) {
			my $newline = shift @{$lines};
			last unless defined $newline;
			$lineno++;
			$newline =~ s/\s+$//s;
			$line = $newline;
			next unless $newline;
			$current =~ s/.$/\n/;
			$current .= $newline;
		}

		my @chars = split //, $current;
		$current = undef;
		my $inquote = 0;

		while (defined(my $c = shift @chars)) {
			if ($c eq q{\\}) {
				$c = shift @chars if @chars;
			}
			elsif ($c eq q{"}) {
				$inquote ^= 1;
			}
			elsif ($c =~ /[;#]/) {
				last unless $inquote;
			}
			$current .= $c;
		}
		last unless $current;

		if ($current =~ /\[(.+)\]/) {

			$section = $opt->{'lowersections'} ? lc $1 : $1;
			$ini->{$section} ||= ();
		}
		elsif ($current =~ /^\s*([^=]+?)\s*=\s*(.*?)\s*$/s) {

			my ($key, $val) = ($1, $2);
			$key = lc $key if $opt->{'lowerkeys'};
			$val = _parse_value($val, $replaces);

			my $rkey = $section eq DEF_SECTION ? '' : "$section/";
			$rkey .= $key;

			if ($multikey{$key}) {
				$ini->{$section}{$key} = ()
					unless ref $ini->{$section}{$key} eq 'ARRAY';
				push @{ $ini->{$section}{$key} }, $val;
				$replaces->{$rkey} = join q{,}, @{ $ini->{$section}{$key} };
			}
			else {
				$ini->{$section}{$key} = $val;
				$replaces->{$rkey} = $val;
			}

		}
		else {
			$error = "Invalid line number $lineno: $line";
			return;
		}
	}

	return wantarray ? %{$ini} : $ini;
}

# ------------------------------------------------------------------------------
sub parse_config_data {
	my ($input, %opt) = @_;

	my %ini;
	my %replaces;

	foreach my $section (keys %{ $opt{'defaults'} }) {

		my $rkey = $section eq DEF_SECTION ? '' : "$section/";

		foreach my $key (keys %{ $opt{'defaults'}{$section} }) {

			$rkey .= $key;

			if (ref $opt{'defaults'}{$section}{$key}) {
				my @val = map { _parse_value($_, \%replaces) }
					@{ $opt{'defaults'}{$section}{$key} };
				$replaces{$rkey} = join q{,}, @val;
				$ini{$section}{$key} = @val;
			}
			else {
				my $val = _parse_value($opt{'defaults'}{$section}{$key},
					\%replaces);
				$replaces{$rkey} = $val;
				$ini{$section}{$key} = $val;
			}
		}
	}

	return _parse([ split /\n/, $input ], \%opt, \%ini, \%replaces);
}

# ------------------------------------------------------------------------------
sub parse_config_file {
	my ($filename, %opt) = @_;
	$error = undef;
	$error = 'No filename given', return
		unless $filename;
	my $encoding
		= $opt{'encoding'} ? '<:encoding(' . $opt{'encoding'} . ')' : '<';
	$error = "Can not open file \"$filename\": $ERRNO", return
		unless open(my $fh, $encoding, $filename);
	my $RC = $INPUT_RECORD_SEPARATOR;
	local $INPUT_RECORD_SEPARATOR = undef;
	my $input = <$fh>;
	close $fh;
	$INPUT_RECORD_SEPARATOR = $RC;
	return parse_config_data($input, %opt);
}

# ------------------------------------------------------------------------------
1;

__END__

=pod

=head1 NAME

ConfigParse

=head1 VERSION

Version 1.003

=head1 SYNOPSIS

    my %config = ConfigParse::parse_config_file( $filename, %options )
    # OR
    my $config = ConfigParse::parse_config_file( $filename, %options )
    # OR
    my %config = ConfigParse::parse_config_data( $string, %options )
    # OR
    my $config = ConfigParse::parse_config_data( $string, %options )

=head1 DESCRIPTION

Default section name is "_".

Use Key = %VALUE% to substitute %VALUE% by environment content.

Use Key = @VALUE@ to substitute @VALUE@ by value computed in the previous steps.

Use "#" or ";" for comments.

Use "\" on line end to continue on next line, or HEREDOC syntax for
multiline values.

Use <I>/* and <I>*/ to separate lines for block comments;

=head1 EXAMPLE

    HereDocValue  <<< _HERE_;
       Here
         Doc
          Value
    _HERE_;

    /*
      Block
        comment
    */
    
    MultiLineValue = multiline \
     value
    QuotedValue = " quoted value "

    [A]
    a = a 	; comment
    [B]
    b = b	# see "multikey" option
    b = c	#
    [C]
    Path = %PATH%
    
    # Use "Path" from "C" section:
    Chemin = "Utilisez le chemin \"@C/Path@\" pour ..." 

=head1 DIAGNOSTICS

    croak $ConfigParse::error if $ConfigParse::error;

=head1 SUBROUTINES/METHODS

=over

=item parse_config_data( I<$string>, I<%options> )
=item parse_config_file( I<$file>, I<%options> )

Valid options are:

<B>encoding      : suggest file content encoding for <B>item parse_config_data.

<B>lowersections : convert section names to lower.

<B>lowerkeys     : convert key names to lower.

<B>defaults      : default values; common (default) section is "_".

<B>multikey      : key names to create multi-values array. For example,
without this key this config secection

    a = b
    a = c
    a = d

produces:

    $data{'a'} => 'd' # last value used

With <I>multikey=>['a']

    $data{'a'} => [ 'b', 'c', 'd' ]

=back

=head1 BUGS AND LIMITATIONS

Invalid block comments examples:

    /* Block comment */

    /* Block
          comment */

=head1 LICENSE AND COPYRIGHT

Coyright (C) 2016 Vsevolod Lutovinov.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. The full text of this license can be found in
the LICENSE file included with this module.

=head1 AUTHOR

Contact the author at klopp@yandex.ru.

=head1 SOURCE CODE

Source code and issues can be found here:
 <https://github.com/klopp/perl-modules>

=cut
