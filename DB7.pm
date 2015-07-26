package DB7;
use strict;
use warnings;
use Const::Fast;
use English qw /-no_match_vars/;

# ------------------------------------------------------------------------------
use vars qw /$VERSION/;
$VERSION = '1.2';

use Data::Dumper;

# ------------------------------------------------------------------------------
const my $DB7_SIGNATURE    => 0x04;
const my $DB7_HEADER_END   => 0x0D;
const my $DB7_FILE_END     => 0x1A;
const my $DB7_CHAR_MAX     => 0xFF;
const my $DB7_CHAR_BITS    => 8;
const my $DB7_INT_MAX      => 2_147_483_647;
const my $DB7_INT_MIN      => -2_147_483_648;
const my $DB7_CHAR_LEN_MAX => 0xFF + ( 0xFF << 8 );
const my $DB7_MONTH_MAX    => 12;
const my $DB7_MDAY_MAX     => 31;
const my $DB7_RECNAME_MAX  => 32;
const my $DB7_RECORD_SIGN  => 32;                   # 32 - regular, 42 - deleted
const my $DB7_DATE_SIZE    => 8;
const my $DB7_BOOL_SIZE    => 1;
const my $DB7_INT_SIZE     => 4;
const my $DB7_DEF_CODEPAGE => 0x01;
const my $DB7_DEF_LANGUAGE => 'DBWINUS0';
const my $DB7_VALID_TYPES  => qr/^[FIDLC]$/;

const my $DB7_HEADER => <<'EOL';
C       //  signature
C3      //  created, YMD
L       //  records number, as 32-bit unsigned
S       //  header size, as 16-bit unsigned
S       //  record size, as 16-bit unsigned
a17     //  reserved[2], dBase IV[2], multiuser[12], MDX[1],
C       //  dBase IV, Visual FoxPro, XBase codepage[1]
S       //  reserved[2]
a32     //  language driver
L       //  reserved[4]
EOL
my $DB7_HEADER_TPL = $DB7_HEADER;
$DB7_HEADER_TPL =~ s{\s+//.+$}{}gm;
$DB7_HEADER_TPL =~ s{\s+}{}g;
const my $DB7_HEADER_SIZE => length( pack $DB7_HEADER_TPL, 0 );

const my $DB7_FIELD_DESCR => <<'EOL';
a32     //  field name
a       //  field type[1]
C       //  field length, 1st byte
C       //  2nd byte of length (type=C) or 0
a13     //  reserved[2], MDX, reserved[2], autoincrement[int32], reserved[4]
EOL
my $DB7_FDESCR_TPL = $DB7_FIELD_DESCR;
$DB7_FDESCR_TPL =~ s{\s+//.+$}{}gm;
$DB7_FDESCR_TPL =~ s{\s+}{}g;
const my $DB7_FDECSR_SIZE => length( pack $DB7_FDESCR_TPL, 0 );

# ------------------------------------------------------------------------------
sub new {
    my ( $class, $opt, @vars ) = @_;

    $opt ||= {};
    my $self = bless $opt, $class;

    $self->{'record_size'} = 0;
    $self->{'header_size'} = $DB7_HEADER_SIZE + 1;
    $self->{'records'}     = ();
    $self->{'vars'}        = ();
    $self->{'error'}       = undef;
    $self->{'dirty'}       = undef;

    $self->{'language'} ||= $DB7_DEF_LANGUAGE;

    if (@vars) {

        foreach my $var (@vars) {
            my $length = length $var->{'name'};
            $self->{'error'}
                = "Invalid name length for \"$var->{'name'}\" ($length chars, $DB7_RECNAME_MAX max)",
                last
                if $length > $DB7_RECNAME_MAX;

            $self->{'error'}
                = "Invalid type \"$var->{'type'}\" for \"$var->{'name'}\"", last
                if $var->{'type'} !~ $DB7_VALID_TYPES;

            $self->{'error'}
                = "Invalid CHAR length \"$var->{'size'}\" for \"$var->{'name'}\"",
                last
                if $var->{'type'} eq 'C'
                && ( !$var->{'size'}
                || $var->{'size'} <= 0
                || $var->{'size'} > $DB7_CHAR_LEN_MAX );

            $var->{'size'} = $DB7_DATE_SIZE if $var->{'type'} eq 'D';
            $var->{'size'} = $DB7_BOOL_SIZE if $var->{'type'} eq 'L';
            $var->{'size'} = $DB7_INT_SIZE  if $var->{'type'} eq 'I';
            $var->{'dec'} ||= 0;
            $self->{'record_size'} += $var->{'size'};
            $self->{'header_size'} += $DB7_FDECSR_SIZE;
            push @{ $self->{'vars'} }, $var;
        }
    }
    else {
        $self->_read_file();
    }

=pod
    foreach my $key ( keys %{$vars} ) {
        my $length = length $key;
        $self->{'error'}
            = "Invalid name length for '$key' ($length chars, 32 max)", last
            if $length > $DB7_RECNAME_MAX;

        $self->{'error'} = "Invalid type '$vars->{$key}->[0]' for '$key'", last
            if $vars->{$key}->[0] !~ $DB7_VALID_TYPES;

        $self->{'vars'}->{$key}->[1] = $DB7_DATE_SIZE
            if $vars->{$key}->[0] eq 'D';
        $self->{'vars'}->{$key}->[1] = $DB7_BOOL_SIZE
            if $vars->{$key}->[0] eq 'L';
        $self->{'vars'}->{$key}->[1] = $DB7_INT_SIZE
            if $vars->{$key}->[0] eq 'I';
        $self->{'record_size'} += $self->{'vars'}->{$key}->[1];
        $self->{'header_size'} += $DB7_FDECSR_SIZE;
    }
=cut

    return $self;
}

# ------------------------------------------------------------------------------
sub errstr {
    my ($self) = @_;
    return $self->{'error'};
}

# ------------------------------------------------------------------------------
sub add_record {
    my ( $self, $data ) = @_;

    return $self->{'error'} if $self->{'error'};

    my @rec;
    foreach my $var ( @{ $self->{'vars'} } ) {
        my $value = $data->{ $var->{'name'} };
        if ($value) {
            $self->_validate_value( $var, $value )
                unless $self->{'nocheck'};
            return $self->{'error'} if $self->{'error'};
        }
        push @rec, $value || '';
    }

    push @{ $self->{'records'} }, [@rec];
    $self->{'dirty'} = 1;
    return;
}

# ------------------------------------------------------------------------------
sub del_record {
    goto &remove_record;
}

# ------------------------------------------------------------------------------
sub remove_record {
    my ( $self, $idx ) = @_;

    return $self->{'error'} if $self->{'error'};

    return $self->_e('Can not delete records from empty set')
        if $#{ $self->{'records'} } < 0;

    return $self->_e( "Invalid index '$idx' (total records: "
            . ( $#{ $self->{'records'} } + 1 )
            . ')' )
        if $idx !~ /^\d+$/ || $idx > $#{ $self->{'records'} };
    splice @{ $self->{records} }, $idx, 1;
    $self->{'dirty'} = 1;
    return;
}

# ------------------------------------------------------------------------------
sub get_record {
    my ( $self, $idx ) = @_;

    return if $self->{'error'};

    return $self->_e( 'Can not get records from empty set', 1 )
        if $#{ $self->{'records'} } < 0;

    return $self->_e(
        "Invalid index '$idx' (total records: "
            . ( $#{ $self->{'records'} } + 1 ) . ')',
        1
    ) if $idx !~ /^\d+$/ || $idx > $#{ $self->{'records'} };
    return $self->{records}->[$idx];

}

# ------------------------------------------------------------------------------
sub get_all_records {
    my ( $self, $idx ) = @_;

    return if $self->{'error'};

    return scalar @{ $self->{'records'} } unless wantarray;

    my @data;

    foreach my $rec ( @{ $self->{'records'} } ) {

        my %rc;
        $rc{ $self->{'vars'}->[$_]->{'name'} } = $rec->[$_]
            for ( 0 .. $#{$rec} );
        push @data, \%rc;
    }
    return \@data;
}

# ------------------------------------------------------------------------------
sub update_record {
    my ( $self, $idx, $data ) = @_;

    return $self->{'error'} if $self->{'error'};

    return $self->_e('Can not update record in empty set')
        if $#{ $self->{'records'} } < 0;

    return $self->_e( "Invalid index '$idx' (total records: "
            . ( $#{ $self->{'records'} } + 1 )
            . ')' )
        if $idx !~ /^\d+$/ || $idx > $#{ $self->{'records'} };

    my $rec = $self->{'records'}->[$idx];

    foreach my $var ( @{ $self->{'vars'} } ) {
        next unless exists $data->{ $var->{'name'} };
        my $value = $data->{ $var->{'name'} };
        if ($value) {
            $self->_validate_value( $var, $value )
                unless $self->{'nocheck'};
            return $self->{'error'} if $self->{'error'};
        }
        $rec->{ $var->[0] } = $value || '';
        $self->{'dirty'} = 1;
    }

=pod
    foreach my $name ( keys %{ $self->{'vars'} } ) {
        next unless exists $data->{$name};
        my $value = $data->{$name};
        if ($value) {
            $self->_validate_value( $name, $value )
                unless $self->{'nocheck'};
            return $self->{'error'} if $self->{'error'};
        }
        $rec->{$name} = $value || '';
    }
=cut

    return;
}

# ------------------------------------------------------------------------------
sub drop_db {
    my ($self) = @_;
    return $self->{'error'} if $self->{'error'};
    $self->{'dirty'} = undef;
    return;
}

# ------------------------------------------------------------------------------
sub close_db {
    my ($self) = @_;

    return $self->{'error'} if $self->{'error'};

    return unless $self->{'dirty'};

    my $filename = $self->{'file'};

    open my $dbf, '>:raw', $filename
        or return $self->_e("Can not OPEN \"$filename\": $ERRNO");
    binmode $dbf;

    return $self->{'error'} if $self->_write_header($dbf);
    foreach my $var ( @{ $self->{'vars'} } ) {
        print {$dbf} pack(
            $DB7_FDESCR_TPL,
            $var->{'name'},
            $var->{'type'},
            ( $var->{'size'} & $DB7_CHAR_MAX ),
            (   $var->{'type'} eq 'C'
                ? ( ( $var->{'size'} >> $DB7_CHAR_BITS ) & $DB7_CHAR_MAX )
                : $var->{'dec'}
            ),
            ''
        );
    }

    print {$dbf} pack( 'C', $DB7_HEADER_END );

    foreach my $record ( @{ $self->{'records'} } ) {

        print {$dbf} pack( 'C', $DB7_RECORD_SIGN );

        for ( 0 .. $#{$record} ) {

            if ( $self->{'vars'}->[$_]->{'type'} eq 'I' ) {
                print {$dbf} pack( 'l>', ( $record->[$_] || 0 ) );
            }
            elsif ( $self->{'vars'}->[$_]->{'type'} eq 'F' ) {
                print {$dbf} pack(
                    'A' . ( $self->{'vars'}->[$_]->{'size'} ),
                    sprintf(
                        '%' . ( $self->{'vars'}->[$_]->{'size'} ) . 's',
                        $record->[$_]
                    )
                );
            }
            else {
                print {$dbf} pack(
                    'A' . ( $self->{'vars'}->[$_]->{'size'} ),
                    $record->[$_]
                );
            }
        }
    }

    print {$dbf} pack( 'C', $DB7_FILE_END );
    close $dbf
        or return $self->_e("Can not CLOSE \"$filename\": $ERRNO");

    return $self->drop_db();
}

# ------------------------------------------------------------------------------
sub DESTROY {
    my ($self) = @_;
    return $self->close_db();
}

# ------------------------------------------------------------------------------
sub _e {
    my ( $self, $error, $undef ) = @_;
    $self->{'error'} = $error;
    return $undef ? undef : $self->{'error'};
}

# ------------------------------------------------------------------------------
sub _validate_value {
    my ( $self, $var, $value ) = @_;

    if ( $var->{'type'} eq 'I' ) {
        if (   $value !~ /^[-+]?\d+$/
            || $value < $DB7_INT_MIN
            || $value > $DB7_INT_MAX )
        {
            return $self->_e("Invalid INTEGER value of '$var->[0]': $value");
        }
    }
    else {
        my $length = length $value;
        if ( $length > $var->{'size'} ) {
            return $self->_e(
                "Too long value for field '$var->{'name'}: $length/"
                    . $var->{'size'} );
        }
    }

    if ( $var->{'type'} eq 'F' ) {
        if ( $value !~ /^[-+]?\d+\.\d+$/ ) {
            return $self->_e("Invalid FLOAT value of '$var->[0]': $value");
        }
    }

    if ( $var->{'type'} eq 'D' ) {
        if (   $value !~ /^\d{4}(\d\d)(\d\d)$/
            || $1 > $DB7_MONTH_MAX
            || $2 > $DB7_MDAY_MAX )
        {
            return $self->_e(
                "Invalid DATE value for '$var->{'name'}': '$value'");
        }
    }

    if (   $var->{'type'} eq 'L'
        && $value !~ /^[TYNF ?]$/i )
    {
        return $self->_e(
            "Invalid LOGICAL value for '$var->{'name'}': '$value'");
    }

    return;
}

# ------------------------------------------------------------------------------
sub _write_header {
    my ( $self, $dbf ) = @_;

    return $self->{'error'} if $self->{'error'};

    my ( undef, undef, undef, $mday, $mon, $year ) = gmtime(time);

    print {$dbf} pack( $DB7_HEADER_TPL,
        $DB7_SIGNATURE,                 $year,
        $mon + 1,                       $mday,
        scalar @{ $self->{'records'} }, $self->{'header_size'},
        $self->{'record_size'},         '',
        $DB7_DEF_CODEPAGE,              0,
        $self->{'language'},            0 );

    return $self->{'error'};
}

# ------------------------------------------------------------------------------
sub _read_file {
    my ($self) = @_;

    my $filename = $self->{'file'};

    open my $dbf, '<:raw', $filename
        or return $self->_e("Can not OPEN \"$filename\": $ERRNO");
    binmode $dbf;

    my $buf;
    close $dbf, return $self->_e("Can not READ \"$filename\": $ERRNO")
        unless read( $dbf, $buf, $DB7_HEADER_SIZE ) == $DB7_HEADER_SIZE;

    (   $self->{'signature'},      undef,
        undef,                     undef,
        $self->{'records_number'}, $self->{'header_size'},
        $self->{'record_size'},    undef,
        undef,                     undef,
        $self->{'language'}
    ) = unpack $DB7_HEADER_TPL, $buf;

    close $dbf,
        return $self->_e("Invalid file signature: \"$self->{'signature'}\"")
        unless $self->{'signature'} == $DB7_SIGNATURE;

    my $readed        = 1;
    my $fields_length = $self->{'header_size'} - $DB7_HEADER_SIZE;

    while ( $readed < $fields_length ) {
        close $dbf, return $self->_e("Can not READ \"$filename\": $ERRNO")
            unless read( $dbf, $buf, $DB7_FDECSR_SIZE ) == $DB7_FDECSR_SIZE;

        my ( $name, $type, $s1, $s2 ) = unpack $DB7_FDESCR_TPL, $buf;

        ($name) = $name =~ /(\w+)/;

        close $dbf, return $self->_e("Invalid type '$type' for '$name'")
            if $type !~ $DB7_VALID_TYPES;
        my %var = ( 'name' => $name, 'type' => $type );
        $var{'dec'}  = $s2            if $type eq 'F';
        $var{'size'} = $s1            if $type eq 'F';
        $var{'size'} = $DB7_BOOL_SIZE if $type eq 'L';
        $var{'size'} = $DB7_DATE_SIZE if $type eq 'D';
        $var{'size'} = $DB7_INT_SIZE  if $type eq 'I';
        $var{'size'} = $s1 + ( $s2 << $DB7_CHAR_BITS )
            if $type eq 'C';

        push @{ $self->{'vars'} }, \%var;
        $readed += $DB7_FDECSR_SIZE;
    }

    close $dbf, return $self->_e("Can not READ \"$filename\": $ERRNO")
        unless read( $dbf, $buf, 1 ) == 1;

    close $dbf,
        return $self->_e(
        sprintf( 'Invalid header end signature: %X', ord($buf) ) )
        unless ord($buf) == $DB7_HEADER_END;

    my $RECORD_TPL = 'C';
    for ( @{ $self->{'vars'} } ) {
        $RECORD_TPL .= sprintf 'a%d', $_->{'size'} if $_->{'type'} eq 'C';
        $RECORD_TPL .= sprintf 'A%d', $_->{'size'} if $_->{'type'} eq 'F';
        $RECORD_TPL .= 'a8' if $_->{'type'} eq 'D';
        $RECORD_TPL .= 'a'  if $_->{'type'} eq 'L';
        $RECORD_TPL .= 'N'  if $_->{'type'} eq 'I';
    }

    for ( 1 .. $self->{'records_number'} ) {
        $readed = read( $dbf, $buf, $self->{'record_size'} + 1 );
        close $dbf, return $self->_e("Can not READ \"$filename\": $ERRNO")
            unless $readed == $self->{'record_size'} + 1;
        my @rec = unpack $RECORD_TPL, $buf;

        my $sign = shift @rec;
        next unless $sign == $DB7_RECORD_SIGN;

        for ( 0 .. $#{ $self->{'vars'} } ) {
            $rec[$_] =~ s/^\s+// if $self->{'vars'}->[$_]->{'type'} eq 'F';
            $rec[$_] =~ s/\s+$// if $self->{'vars'}->[$_]->{'type'} eq 'C';
        }

        push @{ $self->{'records'} }, [@rec];
    }

    return close $dbf
        ? undef
        : $self->_e("Can not CLOSE \"$filename\": $ERRNO");
}

# ------------------------------------------------------------------------------
1;

__END__

=head1 NAME

DB7 - create and write dBase7 files.

=head1 VERSION

Version 1.2

=head1 SYNOPSIS

    use DB7;
    my $db7 = new DB7
    (
      {
        language => 'db866ru0',
        nocheck => 1
      },
      { name => 'INT',  type => 'I' },
      { name => 'CHAR', type => 'C', size => 32 },
      { name => 'DATE', type => 'D' },
      { name => 'BOOL', type => 'L' }
    );
    die $db7->errstr if $db7->errstr;

    die $db7->errstr if $db7->add_record
    (
      {
        INT => 1234,
        DATE => '20150101',
        BOOL => 'Y',
        CHAR => 'Some string'
      }
    );

    die $db7->errstr if $db7->update_record( 0, { INT => 4321 } );

    die $db7->errstr if $db7->del_record( 1 );

    use Data::Dumper;
    my $rec = $db7->first_record();
    while( $rec )
    {
        die $db7->errstr if $db7->errstr;
        print Dumper( $rec );
        $rec = $db7->next_record();
    }

    die $db7->errstr if $db7->close_file();

=head1 DESCRIPTION

This module can write dBase 7 files. 

=head2 SUBROUTINES/METHODS

=over4

=item $pkg->new( I<$options> )
=item $pkg->new( I<$options>, I<@fields> )

Options is hash ref, valid fields are:

B<file> - file to read/write

B<language> - language driver ID, default is 'DBWINUS0' (ANSI)

B<nocheck> - skip values validation if is set

Each field descriptor is hashref:

    { name => 'FIELD_NAME', type => 'FIELD_TYPE' [, size => FIELD_SIZE] }

Valid types: B<'I' (integer), 'L' (logical), 'D' (date), 'C' (character)>.
Size must be included for B<'C'> type only.

=item $self->add_record( I<$record> )

Record is hash ref (name => value). Unknown keys are ignored.

=item $self->remove_record( I<$idx> )
=item $self->del_record( I<$idx> )

Delete record.

=item $self->update_record( I<$idx>, I<$data> )

Update record. Keys not present in I<$data> remain unchanged.

=item $self->get_all_records()

=item $self->get_record( I<$idx> )

=item $self->write_file( I<$filename> )

=item $self->close_db()

=item $self->drop_db()

=item $self->errstr()

=back

=head1 CONFIGURATION AND ENVIRONMENT

Use B<DB7::new()> arguments, no additional configuration required. 

=head1 DIAGNOSTICS

B<DB7::add_record()>, B<DB7::del_record()>, B<DB7::update_record()> 
and B<DB7::write_file()> methods returns undef if success,
or error message. This message can be readed using B<DB7::errstr()> method 
after B<DB7::new()> call also. 

=head1 BUGS AND LIMITATIONS

Known bug: incorrect negative INTEGER handling (map to unsigned).

Works only with field types: 

B<D> date, B<I> integer, B<L> logical, B<C> character 

MDX (indexes) and MEMO are not supported.

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
 
