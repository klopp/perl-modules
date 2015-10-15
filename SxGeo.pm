package SxGeo;

# ------------------------------------------------------------------------------
#   Created on: 28.09.2015, 21:27:28
#   Author    : Vsevolod Lutovinov <klopp@yandex.ru>
#   based on  : Geo::SypexGeo by Andrey Kuzmin
# ------------------------------------------------------------------------------
use Modern::Perl;
use English qw/-no_match_vars/;
use Exporter;
use base qw/Exporter/;

use Const::Fast;
use Socket qw/inet_aton/;
use Encode qw/encode_utf8 decode_utf8/;
use Data::Validate::IP qw/is_ipv4/;
use experimental qw/switch/;

use vars qw/$VERSION @EXPORT/;
$VERSION = '1.002';
@EXPORT  = qw/$SXGEO_BATCH $SXGEO_MEM/;

# ------------------------------------------------------------------------------
const my @ID2ISO => qw( AP EU AD AE AF AG AI AL AM CW AO AQ AR AS AT AU AW AZ 
    BA BB BD BE BF BG BH BI BJ BM BN BO BR BS BT BV BW BY BZ 
    CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CX CY CZ 
    DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR SX 
    GA GB GD GE GF GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU 
    ID IE IL IN IO IQ IR IS IT JM JO JP KE KG KH KI KM KN KP KR KW KY KZ 
    LA LB LC LI LK LR LS LT LU LV LY 
    MA MC MD MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ 
    NA NC NE NF NG NI NL NO NP NR NU NZ OM 
    PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RU RW 
    SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR ST SV SY SZ 
    TC TD TF TG TH TJ TK TM TN TO TL TR TT TV TW TZ 
    UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT RS 
    ZA ZM ME ZW A1 XK O1 AX GG IM JE BL MF BQ SS
);
const my $HEADER_LENGTH => 40;
const my $SXGEO_BATCH   => 1;
const my $SXGEO_MEM     => 2;

# ------------------------------------------------------------------------------
use fields qw(
    b_idx_str m_idx_str range b_idx_len m_idx_len db_items id_len
    block_len max_region max_city db_begin regions_begin cities_begin
    max_country country_size pack error b_idx_arr m_idx_arr
    filebuf fd batch_mode mem_mode offset
);

# ------------------------------------------------------------------------------
sub bin2hex {
    my $str = shift;
    my $res = '';
    for my $i ( 0 .. length($str) - 1 ) {
        $res
            .= sprintf( '%02s', sprintf( '%x', ord( substr( $str, $i, 1 ) ) ) );
    }
    return $res;
}

# ------------------------------------------------------------------------------
sub ip2long {
    my ($ip) = @_;
    return unpack( 'l*', pack( 'l*', unpack( 'N*', inet_aton($ip) ) ) );
}

# ------------------------------------------------------------------------------
sub _read {
    my ( $self, $length, $offset ) = @_;
    my $buf;

    if ( $self->{'mem_mode'} ) {
        $self->{'offset'} = $offset if defined $offset;
        $buf = substr( $self->{'filebuf'}, $self->{'offset'}, $length );
        $self->{'offset'} += $length;
    }
    else {
        seek $self->{'fd'}, $offset, 0 if defined $offset;
        read $self->{'fd'}, $buf, $length;
    }
    return $buf;
}

# ------------------------------------------------------------------------------
sub DESTROY {
    return shift->_close();
}

# ------------------------------------------------------------------------------
sub _close {
    my $self = shift;
    close $self->{'fd'} if $self->{'fd'};
    undef $self->{'fd'};
    return $self;
}

# ------------------------------------------------------------------------------
sub new {
    my ( $class, $file, $flags ) = @_;

    $flags ||= 0;

    my $self = fields::new($class);
    my $header;

    $self->{'offset'} = 0;

    if ( !open( $self->{'fd'}, '<', $file ) ) {
        $self->{'error'} = "Can not open file \"$file\": $OS_ERROR";
        return $self;
    }
    binmode $self->{'fd'}, ':bytes';
    if ( $flags & $SXGEO_MEM ) {
        $self->{'mem_mode'} = 1;
        local $INPUT_RECORD_SEPARATOR = undef;
        my $fd = $self->{'fd'};
        $self->{'filebuf'} = <$fd>;
        $self->_close();
    }

    $header = $self->_read($HEADER_LENGTH);

    #  croak 'File format is wrong' if substr( $header, 0, 3 ) ne 'SxG';
    if ( substr( $header, 0, 3 ) ne 'SxG' ) {
        $self->{'error'} = 'File format is wrong';
        return $self->_close();
    }

    my $info_str = substr( $header, 3, $HEADER_LENGTH - 3 );
    my @info = unpack 'CNCCCnnNCnnNNnNn', $info_str;
    if ( $info[4] * $info[5] * $info[6] * $info[7] * $info[1] * $info[8] == 0 )
    {
        $self->{'error'} = 'File header format is wrong';
        return $self->_close();
    }

    if ( $info[15] ) {
        my $pack = $self->_read( $info[15] );
        $self->{'pack'} = [ split "\0", $pack ];
    }

    $self->{b_idx_str} = $self->_read( $info[4] * 4 );
    $self->{m_idx_str} = $self->_read( $info[5] * 4 );

    $self->{range}      = $info[6];
    $self->{b_idx_len}  = $info[4];
    $self->{m_idx_len}  = $info[5];
    $self->{db_items}   = $info[7];
    $self->{id_len}     = $info[8];
    $self->{block_len}  = 3 + $self->{id_len};
    $self->{max_region} = $info[9];
    $self->{max_city}   = $info[10];

    #    $self->{region_size}  = $info[11];
    #    $self->{city_size}    = $info[12];
    $self->{max_country}  = $info[13];
    $self->{country_size} = $info[14];

    $self->{db_begin}
        = $HEADER_LENGTH + $info[15] + ( $info[4] * 4 ) + ( $info[5] * 4 );

    if ( $flags & $SXGEO_BATCH ) {
        $self->{'batch_mode'} = 1;
        @{ $self->{'b_idx_arr'} } = unpack( 'N*', $self->{'b_idx_str'} );
        undef $self->{'b_idx_str'};
        @{ $self->{'m_idx_arr'} } = unpack( '(a4)*', $self->{'m_idx_str'} );
        undef $self->{'b_idx_str'};
    }

    $self->{regions_begin}
        = $self->{db_begin} + $self->{db_items} * $self->{block_len};
    $self->{cities_begin} = $self->{regions_begin} + $info[11];

    return $self;
}

# ------------------------------------------------------------------------------
sub error {
    my $self = shift;
    my $e    = $self->{'error'};
    eval { $e = decode_utf8($e) if $e; };
    return $e;
}

# ------------------------------------------------------------------------------
sub get {
    my ( $self, $ip, @fields ) = @_;

    undef $self->{'error'};
    if ( !is_ipv4($ip) ) {
        $self->{'error'} = "Invalid IP: \"$ip\"";
        return;
    }

    my $seek = $self->get_num($ip);
    return unless $seek;

    my %geodata;

    if ( !$self->{'max_city'} ) {
        %geodata = (
            'country_id'  => $seek,
            'country_iso' => lc $ID2ISO[ $seek - 1 ],
        );
    }
    else {
        my @data = $self->parse_city($seek);
        return unless @data;

        eval { $data[5] = decode_utf8( $data[5] ); };

        %geodata = (
            'region_id'   => $data[0],
            'country_id'  => $data[1],
            'country_iso' => lc $ID2ISO[ $data[1] - 1 ],
            'city_id'     => $data[2],
            'lat'         => $data[3],
            'lon'         => $data[4],
            'city_ru'     => $data[5],
            'city_en'     => $data[6],
        );
    }

    if (@fields) {
        my %rc;
        for (@fields) {
            $rc{$_} = $geodata{$_} if $geodata{$_};
        }
        return wantarray ? %rc : \%rc;
    }

    return wantarray ? %geodata : \%geodata;
}

# ------------------------------------------------------------------------------
sub get_num {

    my ( $self, $ip ) = @_;

    my $ip1n;
    $ip =~ /^(\d+)[.]/ and $ip1n = $1;

    if (  !$ip1n
        || $ip1n == 10
        || $ip1n == 127
        || $ip1n >= $self->{'b_idx_len'} )
    {
        $self->{'error'} = "Invalid IP: \"$ip\"";
        return;
    }
    my $ipn = ip2long($ip);
    $ipn = pack( 'N', $ipn );

    my @blocks;
    if ( $self->{'batch_mode'} ) {
        $blocks[0] = $self->{'b_idx_arr'}->[ $ip1n - 1 ];
        $blocks[1] = $self->{'b_idx_arr'}->[$ip1n];
    }
    else {
        @blocks = unpack 'NN',
            substr( $self->{b_idx_str}, ( $ip1n - 1 ) * 4, 8 );
    }

    my $min;
    my $max;

    if ( $blocks[1] - $blocks[0] > $self->{range} ) {
        my $part = $self->search_idx(
            $ipn,

            int( $blocks[0] / $self->{'range'} ),
            int( $blocks[1] / $self->{'range'} )
                - 1

                #            floor( $blocks[0] / $self->{'range'} ),
                #            floor( $blocks[1] / $self->{'range'} ) - 1
        );

        $min = $part > 0 ? $part * $self->{range} : 0;
        $max
            = $part > $self->{m_idx_len}
            ? $self->{db_items}
            : ( $part + 1 ) * $self->{range};

        $min = $blocks[0] if $min < $blocks[0];
        $max = $blocks[1] if $max > $blocks[1];
    }
    else {
        $min = $blocks[0];
        $max = $blocks[1];
    }

    my $len = $max - $min;
    my $buf = $self->_read( $len * $self->{block_len},
        $self->{db_begin} + $min * $self->{block_len} );

    return $self->search_db( $buf, $ipn, 0, $len - 1 );
}

# ------------------------------------------------------------------------------
sub search_idx {
    my ( $self, $ipn, $min, $max ) = @_;

    $ipn = encode_utf8($ipn);
    my $offset;

    if ( $self->{'batch_mode'} ) {
        while ( $max - $min > 8 ) {
            $offset = ( $min + $max ) >> 1;
            if ( $ipn gt encode_utf8( $self->{m_idx_arr}->[$offset] ) ) {
                $min = $offset;
            }
            else {
                $max = $offset;
            }
        }
        while ($ipn gt encode_utf8( $self->{m_idx_arr}->[$min] )
            && $min++ < $max )
        {
        }
    }
    else {
        while ( $max - $min > 8 ) {
            $offset = ( $min + $max ) >> 1;
            if ( $ipn
                gt encode_utf8(
                    substr( ( $self->{m_idx_str} ), $offset * 4, 4 ) ) )
            {
                $min = $offset;
            }
            else {
                $max = $offset;
            }
        }
        while ($ipn gt encode_utf8( substr( $self->{m_idx_str}, $min * 4, 4 ) )
            && $min++ < $max )
        {
        }
    }
    return $min;
}

# ------------------------------------------------------------------------------
sub search_db {
    my ( $self, $str, $ipn, $min, $max ) = @_;

    if ( $max - $min > 1 ) {
        $ipn = substr( $ipn, 1 );
        my $offset;
        while ( $max - $min > 8 ) {
            $offset = ( $min + $max ) >> 1;

            if ( encode_utf8($ipn)
                gt encode_utf8(
                    substr( $str, $offset * $self->{block_len}, 3 ) ) )
            {
                $min = $offset;
            }
            else {
                $max = $offset;
            }
        }

        while ( encode_utf8($ipn)
            ge encode_utf8( substr( $str, $min * $self->{block_len}, 3 ) )
            && $min++ < $max )
        {
        }
    }
    else {
        return
            hex( bin2hex( substr( $str, $min * $self->{block_len} + 3, 3 ) ) );
    }

    return hex(
        bin2hex(
            substr(
                $str, $min * $self->{block_len} - $self->{id_len},
                $self->{id_len}
            )
        )
    );
}

# ------------------------------------------------------------------------------
sub parse_city {
    my ( $self, $seek ) = @_;

    my @info;
    my $buf;

    if ( $seek < $self->{country_size} ) {
        $buf = $self->_read( $self->{max_country},
            $seek + $self->{cities_begin} );
        @info = $self->extended_unpack( $self->{'pack'}[0], $buf );
    }
    else {
        $buf = $self->_read( $self->{max_city}, $seek + $self->{cities_begin} );
        @info = $self->extended_unpack( $self->{'pack'}[2], $buf );
    }

    return @info;
}

# ------------------------------------------------------------------------------
sub extended_unpack {

    my ( $self, $flags, $val ) = @_;

    my $pos = 0;
    my @result;

    my @flags_arr = split q{/}, $flags;

    foreach my $flag_str (@flags_arr) {
        my ( $type, $name ) = split q{:}, $flag_str;

        my $flag = substr $type, 0, 1;
        my $num  = substr $type, 1, 1;

        my $len;

        given ($flag) {
            when ('t') {
            }
            when ('T') {
                $len = 1;
            }
            when ('s') {
            }
            when ('n') {
                $len = $num;
            }
            when ('S') {
                $len = 2;
            }
            when ('m') {
            }
            when ('M') {
                $len = 3;
            }
            when ('d') {
                $len = 8;
            }
            when ('c') {
                $len = $num;
            }
            when ('b') {
                $len = index( $val, "\0", $pos ) - $pos;
            }
            default {
                $len = 4;
            }
        }

        my $subval = substr( $val, $pos, $len );

        my $res;

        given ($flag) {
            when ('t') {
                $res = ( unpack 'c', $subval )[0];
            }
            when ('T') {
                $res = ( unpack 'C', $subval )[0];
            }
            when ('s') {
                $res = ( unpack 's', $subval )[0];
            }
            when ('S') {
                $res = ( unpack 'S', $subval )[0];
            }
            when ('m') {
                $res = (
                    unpack 'l',
                    $subval
                        . (
                        ord( substr( $subval, 2, 1 ) ) >> 7 ? "\xff" : "\0" )
                )[0];
            }
            when ('M') {
                $res = ( unpack 'L', $subval . "\0" )[0];
            }
            when ('i') {
                $res = ( unpack 'l', $subval )[0];
            }
            when ('I') {
                $res = ( unpack 'L', $subval )[0];
            }
            when ('f') {
                $res = ( unpack 'f', $subval )[0];
            }
            when ('d') {
                $res = ( unpack 'd', $subval )[0];
            }
            when ('n') {
                $res = ( unpack 's', $subval )[0] / ( 10**$num );
            }
            when ('N') {
                $res = ( unpack 'l', $subval )[0] / ( 10**$num );
            }
            when ('c') {
                $res = rtrim $subval;
            }
            when ('b') {
                $res = $subval;
                $len++;
            }
        }

        $pos += $len;

        push @result, $res;
    }

    return @result;
}

# ------------------------------------------------------------------------------

1;

__END__

=head1 NAME

SxGeo - L<Sypex Geo|https://sypexgeo.net/> databases parser

=head1 VERSION

Version 1.002

=head1 SYNOPSIS

    use SxGeo;

    my $sxgeo = SxGeo->new( 'SxGeo.dat' );
    my $geodata = $sxgeo->get( '93.191.14.81' ); 
    
=head1 DESCRIPTION

This module parse L<Sypex Geo|http://sypexgeo.net/> databases and allow to get geo information for IP.

=head1 SUBROUTINES/METHODS

=encoding UTF-8

=over

=item new( F<$file> [, $flags] )

Valid C<$flags> values: C<$SXGEO_BATCH> (for multiple C<get> requests), C<$SXGEO_MEM>.  

=item get( I<$ip> [, @fields] )

Return geodata or undef.

    use Data::Printer;
    my $geodata = $sxgeo->get( '93.191.14.81' );
    p $geodata; 

Output:

    \ {
        city_en       "Fryazino",
        city_id       562319,
        city_ru       "Фрязино",
        country_id    185,
        country_iso   "ru",
        lat           55.96056,
        lon           38.04556,
        region_id     10267
    }

You can indicate fields to return:

    my $geodata = $sxgeo->get( '93.191.14.81', 'city_en', 'lat', 'lon' );
    p $geodata; 

Output:

    \ {
        city_en       "Fryazino",
        lat           55.96056,
        lon           38.04556,
    }

For F<SxGeo.dat> only two field avaliable: C<country_id>, C<country_iso>.

=item error

Return internal error string. Example:

    my $geodata = $sxgeo->get( '666.356.299.400' ); 
    say $sxgeo->error unless $geodata;

=back

=head1 BUGS AND LIMITATIONS

With C<$SXGEO_MEM> flag entire file will be loaded into memory!

=head1 LICENSE AND COPYRIGHT

Coyright (C) 2015 Vsevolod Lutovinov.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. The full text of this license can be found in
the LICENSE file included with this module.

=head1 AUTHOR

Contact the author at klopp@yandex.ru.

=head1 SOURCE CODE

Source code and issues can be found here:
 <https://github.com/klopp/sxgeo-perl>

