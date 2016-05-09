package ConfigParse;

# ------------------------------------------------------------------------------
use Modern::Perl;
use English qw/-no_match_vars/;

# ------------------------------------------------------------------------------
use Exporter;
use base qw/Exporter/;
use vars qw/$VERSION $error @EXPORT_OK/;
$VERSION   = '1.003';
@EXPORT_OK = qw/parse_config_file parse_config_data/;

# ------------------------------------------------------------------------------
sub _parse {
	my ($lines, $opt) = @_;

	my $current;
	my $section = q{_};
	my $lineno  = 0;
	my $line;
	my %ini;
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
			$ini{$section} ||= ();
		}
		elsif ($current =~ /^\s*([^=]+?)\s*=\s*(.*?)\s*$/s) {

			my ($key, $val) = ($1, $2);
			$key = lc $key if $opt->{'lowerkeys'};
			$val =~ s/^"|"$//gs;

			if ($multikey{$key}) {
				$ini{$section}{$key} = []
					unless $ini{$section}{$key};
				push @{ $ini{$section}{$key} }, $val;
			}
			else {
				$ini{$section}{$key} = $val;
			}

		}
		else {
			$error = "Invalid line number $lineno: $line";
			return;
		}
	}
	return %ini;
}

# ------------------------------------------------------------------------------
sub _parse_env {
	my ($ini) = @_;

	foreach my $section (keys %{$ini}) {
		foreach my $key (keys %{ $ini->{$section} }) {

			if (ref $ini->{$section}{$key}) {

				for (0 .. $#{ $ini->{$section}{$key} }) {
					next
						unless $ini->{$section}{$key}[$_] =~ /^%(.+)%$/;
					$ini->{$section}{$key}[$_] = $ENV{$1};
				}
			}
			else {
				next unless $ini->{$section}{$key} =~ /^%(.+)%$/;
				$ini->{$section}{$key} = $ENV{$1};
			}
		}
	}
	return wantarray ? %{$ini} : $ini;
}

# ------------------------------------------------------------------------------
sub parse_config_data {
	my ($input, %opt) = @_;

	my %ini = _parse([ split /\n/, $input ], \%opt);
	unless ($opt{'defaults'}) {
		return _parse_env(\%ini);
	}

	my %rc;

	foreach my $key (keys %{ $opt{'defaults'} }) {
		$rc{$key}{$_} = $opt{'defaults'}->{$key}->{$_}
			for keys %{ $opt{'defaults'}->{$key} };
	}
	foreach my $key (keys %ini) {
		$rc{$key}{$_} = $ini{$key}->{$_} for keys %{ $ini{$key} };
	}
	return _parse_env(\%rc);
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
	local $INPUT_RECORD_SEPARATOR = undef;
	my $input = <$fh>;
	close $fh;
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

<B>defaults      : default values.

<B>multikey      : key names to create multi-values array. For example,
without this key this config secection

    a = b
    a = c
    a = d

produces:

    $data{'a'} => 'b'

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
