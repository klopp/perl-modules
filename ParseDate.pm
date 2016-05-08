package ParseDate;

# ---------------------------------------------------------------------
use Exporter;
use vars qw(%sseconds %nmonths $MONTHRX $DATERX $TIMERX %MATCHES $RX00);
@ISA    = qw(Exporter);
@EXPORT = qw(parseDate string2Seconds parseDateInfo);

# -------------------------------------------------------------------------
use strict;
use utf8;
use Date::Manip;
use Time::Local;
use POSIX qw(floor);

# -------------------------------------------------------------------------
%nmonths = (
    'янв'         => 0, 'фев'         => 1,   'мар'           => 2,
    'апр'         => 3, 'май'         => 4,   'июн'           => 5,
    'июл'         => 6, 'авг'         => 7,   'сен'           => 8,
    'окт'         => 9, 'ноя'         => 10,  'дек'           => 11,
    'январь'   => 0, 'февраль' => 1,   'март'         => 2,
    'апрель'   => 3, 'май'         => 4,   'июнь'         => 5,
    'июль'       => 6, 'август'   => 7,   'сентябрь' => 8,
    'октябрь' => 9, 'ноябрь'   => 10,  'декабрь'   => 11,
    'января'   => 0, 'февраля' => 1,   'марта'       => 2,
    'апреля'   => 3, 'мая'         => '4', 'июня'         => 5,
    'июля'       => 6, 'августа' => 7,   'сентября' => 8,
    'октября' => 9, 'ноября'   => 10,
    'декабря' => 11,
    'jan'            => 0, 'feb'            => 1,   'mar'              => 2,
    'apr'            => 3, 'may'            => 4,   'jun'              => 5,
    'jul'            => 6, 'aug'            => 7,   'sep'              => 8,
    'oct'            => 9, 'nov'            => 10,  'dec'              => 11,
    'january'        => 0, 'february'       => 1,   'march'            => 2,
    'april'          => 3, 'may'            => 4,   'june'             => 5,
    'july'           => 6, 'august'         => 7,   'september'        => 8,
    'october'        => 9, 'november'       => 10,  'december'         => 11 );

# -------------------------------------------------------------------------
$MONTHRX = undef;
$DATERX  = '(\d{1,2})(?:th|nd|rd|st){0,1}';
$TIMERX  = '(\d{1,2}:\d{1,2}(?::\d{1,2}){0,1}\s*(?:AM|PM){0,1})';
$RX00    = qr/^\d+$/o;

# -------------------------------------------------------------------------
sub _getMonth
{
    my ( $m ) = @_;
    $m = lc $m;
    return $nmonths{$m} ? $nmonths{$m} : $m;
}

# -------------------------------------------------------------------------
%MATCHES = (

    '5' => [    # 123 дня назад
        sub {
            my ( $now, $data ) = @_;

            $now - ( 60 * 60 * 24 ) * $data->[0];
            }
    ],

    '10' => [    # меньше минуты назад
        sub {
            my ( $now, $data ) = @_;
            floor( $now / 60 ) * 60;
            }
    ],

    '15' => [    # 2 часа назад
        sub {
            my ( $now, $data ) = @_;
            $now - ( 60 * 60 * $data->[0] );
            }
    ],

    '20' => [    # 10 минут назад
        sub {
            my ( $now, $data ) = @_;
            floor( ( $now - ( 60 * $data->[0] ) ) / 60 ) * 60;
            }
    ],

    '30' => [    # сегодня 22:22
        sub {
            my ( $now, $data ) = @_;
            my ( undef, undef, undef, $mday, $mon, $year ) = localtime( $now );
            my ( $hour, $min, $sec ) = split( /:/, $data->[0] );
            timelocal( $sec, $min, $hour, $mday, $mon, $year + 1900 );
            }
    ],

    '40' => [    # вчера 22:22
        sub {
            my ( $now, $data ) = @_;
            my ( undef, undef, undef, $mday, $mon, $year ) = localtime( $now );
            $mday--;
            unless( $mday )
            {
                $mon--;
                $mon = 0, $year-- if $mon < 0;
                $mday = Date_DaysInMonth( $mon + 1, $year + 1900 );
            }
            my ( $hour, $min, $sec ) = split( /:/, $data->[0] );
            timelocal( $sec, $min, $hour, $mday, $mon, $year + 1900 );
            }
    ],

    '50' => [    # 22.12.2004 12:13:14
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[3] );
            timelocal(
                $sec, $min, $hour, $data->[0], $data->[1] - 1,
                $data->[2] );
            }
    ],

    '55' => [    # 2004.12.22 12:13:14
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[3] );
            timelocal(
                $sec, $min, $hour, $data->[1], $data->[1] - 1,
                $data->[0] );
            }
    ],

    '60' => [    # 22-12-2004 12:13:14
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[3] );
            timelocal(
                $sec, $min, $hour, $data->[0], $data->[1] - 1,
                $data->[2] );
            }
    ],

    '65' => [    # 2004-12-22 12:13:14
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[3] );
            timelocal(
                $sec, $min, $hour, $data->[2], $data->[1] - 1,
                $data->[0] );
            }
    ],

    '70' => [    # 12:13:14 22.12.2004
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[0] );
            timelocal(
                $sec, $min, $hour, $data->[1], $data->[2] - 1,
                $data->[3] );
            }
    ],

    '80' => [    # 12:13:14 22-12-2004
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[0] );
            timelocal(
                $sec, $min, $hour, $data->[1], $data->[2] - 1,
                $data->[3] );
            }
    ],

    '90' => [    # 12 Apr 2004 12:13:14
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[3] );
            timelocal(
                $sec, $min, $hour, $data->[0], _getMonth( $data->[1] ),
                $data->[2] );
            }
    ],

    '100' => [    # Apr 12 2004 12:13:14
        sub {
            my ( $now, $data ) = @_;
            my ( $hour, $min, $sec ) = split( /:/, $data->[3] );
            timelocal(
                $sec, $min, $hour, $data->[1], _getMonth( $data->[0] ),
                $data->[2] );
            }
    ],

    '110' => [    # 12 Mar 22:22
        sub {
            my ( $now, $data ) = @_;
            my ( undef, undef, undef, undef, undef, $year ) = localtime( $now );
            my ( $hour, $min, $sec ) = split( /:/, $data->[2] );
            timelocal(
                $sec, $min, $hour, $data->[0], _getMonth( $data->[1] ),
                $year + 1900 );
            }
    ],

    '120' => [    # 12 Mar 2004
        sub {
            my ( $now, $data ) = @_;
            timelocal(
                3, 2, 1, $data->[0], _getMonth( $data->[1] ),
                $data->[2] );
            }
    ],

    '130' => [    # 12.08.2004
        sub {
            my ( $now, $data ) = @_;
            timelocal(
                3, 2, 1, $data->[0], $data->[1] - 1,
                $data->[2] );
            }
    ],

    '140' => [    # 2004.08.22
        sub {
            my ( $now, $data ) = @_;
            timelocal(
                3, 2, 1, $data->[2], $data->[1] - 1,
                $data->[0] );
            }
    ],

    '150' => [    # 12-08-2004
        sub {
            my ( $now, $data ) = @_;
            timelocal(
                3, 2, 1, $data->[0], $data->[1] - 1,
                $data->[2] );
            }
    ],

    '160' => [    # 2004-08-22
        sub {
            my ( $now, $data ) = @_;
            timelocal(
                3, 2, 1, $data->[2], $data->[1] - 1,
                $data->[0] );
            }
    ],

);

# -------------------------------------------------------------------------
sub parseDateInfo
{
    return { 'cases' => scalar keys %MATCHES };
}

# -------------------------------------------------------------------------
sub parseDate
{
    my ( $d, $now ) = @_;

    my $s = $d;
    $s =~ s/^\s+|\s+$//gsm;
    return $s if $s =~ /$RX00/;

    unless( $MONTHRX )
    {
        $MONTHRX .= '('
            . join( '|', sort { length $b <=> length $a } keys %nmonths ) . ')';

        $MATCHES{5}->[1] =
            qr/^(.*?)(\d+)\s+?(?:дн|дн\.|дня|дней)\s+?назад/oi;

        $MATCHES{10}->[1] =
            qr/^(.*?)^меньше.+?минуты.+?назад/oi;

        $MATCHES{15}->[1] =
            qr/^(.*?)(\d+)\s+?(?:ч|ч\.|час|часа).+?назад/oi;

        $MATCHES{20}->[1] =
            qr/^(.*?)(\d+)\s+?(?:минут|мин|мин\.).+?назад/oi;
        $MATCHES{30}->[1] = qr/^(.*?)сегодня.+?$TIMERX/oi;
        $MATCHES{40}->[1] = qr/^(.*?)вчера.+?$TIMERX/oi;

        # 22.12.2004 12:13:14
        $MATCHES{50}->[1] = qr/^(.*?)$DATERX\.(\d{1,2})\.(\d{4}).+?$TIMERX/oi;

        # 2004.12.22 12:13:14
        $MATCHES{55}->[1] = qr/^(.*?)(\d{4})\.(\d{1,2})\.$DATERX.+?$TIMERX/oi;

        # 22-12-2004 12:13:14
        $MATCHES{60}->[1] = qr/^(.*?)$DATERX\-(\d{1,2})\-(\d{4}).+?$TIMERX/oi;

        # 2004-12-22 12:13:14
        $MATCHES{65}->[1] = qr/^(.*?)(\d{4})\-(\d{1,2})\-$DATERX.+?$TIMERX/oi;

        # 12:13:14 22.12.2004
        $MATCHES{70}->[1] = qr/^(.*?)$TIMERX.+?$DATERX\.(\d{1,2})\.(\d{4})/oi;

        # 12:13:14 22-12-2004
        $MATCHES{80}->[1] = qr/^(.*?)$TIMERX.+?$DATERX\-(\d{1,2})\-(\d{4})/oi;

        # 12 Apr 2004 12:13:14
        $MATCHES{90}->[1] = qr/^(.*?)$DATERX\s+$MONTHRX.+?(\d{4}).+?$TIMERX/oi;

        # Apr 12 2004 12:13:14
        $MATCHES{100}->[1] = qr/^(.*?)$MONTHRX\s+$DATERX.+?(\d{4}).+?$TIMERX/oi;

        # 12 Mar 22:22
        $MATCHES{110}->[1] = qr/^(.*?)$DATERX\s+$MONTHRX.+?$TIMERX/oi;

        # 12 Mar 2004
        $MATCHES{120}->[1] = qr/^(.*?)$DATERX\s+$MONTHRX.+?(\d{4})/oi;

        # 12.08.2004
        $MATCHES{130}->[1] = qr/^(.*?)$DATERX\.(\d\d)\.(\d{4})/oi;

        # 2004.08.22
        $MATCHES{140}->[1] = qr/^(.*?)(\d{4})\.(\d\d)\.$DATERX/oi;

        # 12-08-2004
        $MATCHES{150}->[1] = qr/^(.*?)$DATERX\-(\d\d)\-(\d{4})/oi;

        # 2004-08-22
        $MATCHES{160}->[1] = qr/^(.*?)(\d{4})\-(\d\d)\-$DATERX/oi;
    }

    $now ||= time();
    $s =~ s/yesterday/вчера/igsm;
    $s =~ s/today/сегодня/igsm;

    my $case = -1;
    my $st   = -1;
    my %cases;

    for( sort { $b <=> $a } keys %MATCHES )
    {
        if( $s =~ /$MATCHES{$_}->[1]/ )
        {
            $case = $_;
            $cases{$case} = [ length $1, $2, $3, $4, $5 ];
        }
    }

    if( exists $cases{$case} )
    {
        my $best_case   = $case;
        my $best_offset = length $s;

        for( sort { $b <=> $a } keys %cases )
        {
            $best_case = $_, $best_offset = $cases{$_}[0]
                if $cases{$_}[0] <= $best_offset;
        }

        my $data = $cases{$best_case};
        shift @$data;

        if(    !$MATCHES{$best_case}
            || !$MATCHES{$best_case}->[0]
            || ref $MATCHES{$best_case}->[0] ne 'CODE' )
        {
            $st = 1609448461;    # '01 Jan 2021 01:01:01'
        }
        else
        {
            $st = $MATCHES{$best_case}->[0]( $now, $data );
        }
    }

    return wantarray ? ( $st, $s, $case, $d ) : $st;
}

# -------------------------------------------------------------------------
%sseconds = (
    'week'    => 60 * 60 * 24 * 7,
    'weeks'   => 60 * 60 * 24 * 7,
    'day'     => 60 * 60 * 24,
    'days'    => 60 * 60 * 24,
    'hrs'     => 60 * 60,
    'hour'    => 60 * 60,
    'hours'   => 60 * 60,
    'min'     => 60,
    'minute'  => 60,
    'minutes' => 60,
    'sec'     => 1,
    'second'  => 1,
    'seconds' => 1, );

# -------------------------------------------------------------------------
# '2 weeks, 31 day, 44 hours; 78 min 2 second' => XYZ seconds
# -------------------------------------------------------------------------
sub string2Seconds
{
    my ( $s ) = @_;
    my $seconds = 0;
    while( $s =~ /(\d+)[\s,;]+(\w+)/gsm )
    {
        $seconds += $sseconds{$2} * $1 if $sseconds{$2};
    }
    return $seconds;
}

# -------------------------------------------------------------------------
1;
