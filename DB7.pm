# ------------------------------------------------------------------------------
package DB7;
use strict;
use warnings;
use Const::Fast;
use English qw /-no_match_vars/;

# ------------------------------------------------------------------------------
use vars qw /$VERSION/;
$VERSION = '1.0';

# ------------------------------------------------------------------------------
const my $DB7_SIGNATURE    => 0x04;
const my $DB7_HEADER_END   => 0x0D;
const my $DB7_FILE_END     => 0x1A;
const my $DB7_CHAR_MAX     => 255;
const my $DB7_CHAR_BITS    => 8;
const my $DB7_INT_MAX      => 2_147_483_647;
const my $DB7_INT_MIN      => -2_147_483_648;
const my $DB7_RECNAME_MAX  => 32;
const my $DB7_DEF_CODEPAGE => 0x01;
const my $DB7_DEF_LANGUAGE => 'DBWINUS0';
const my $DB7_HEADER       => <<'EOL';
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
const my $DB7_FIELD_DESCR =>  <<'EOL'; 
a32     //  field name
a       //  field type[1]
C       //  field length, 1st byte
C       //  2nd byte of length (type=C) or 0
a13     //  reserved[2], MDX, reserved[2], autoincrement[int32], reserved[4]
EOL

# ------------------------------------------------------------------------------
sub new
{
    my ( $class, $opt, $vars ) = @_;

    my $self = bless $opt, $class;

    $self->{'vars'}        = $vars;
    $self->{'record_size'} = 0;
    $self->{'header_size'} = 69;
    $self->{'records'}     = [];
    $self->{'error'}       = undef;

    $self->{'language'} ||= $DB7_DEF_LANGUAGE;

    foreach my $key ( keys %{$vars} )
    {
        my $length = length $key;
        $self->{'error'} =
            "Invalid name length for '$key' ($length chars, 32 max)", last
            if $length > $DB7_RECNAME_MAX;

        $self->{'error'} =
            "Invalid type '" . $vars->{$key}->[0] . "' for '$key'", last
            if $vars->{$key}->[0] !~ /^[IDLC]$/;

        $self->{'vars'}->{$key}->[1] = 8 if $vars->{$key}->[0] eq 'D';
        $self->{'vars'}->{$key}->[1] = 1 if $vars->{$key}->[0] eq 'L';
        $self->{'record_size'} += $self->{'vars'}->{$key}->[1];
        $self->{'header_size'} += 48;
    }

    return $self;
}

# ------------------------------------------------------------------------------
sub errstr
{
    my ( $self ) = @_;
    return $self->{'error'};
}

# ------------------------------------------------------------------------------
sub _e
{
    my ( $self, $error ) = @_;
    $self->{'error'} = $error;
    return $self->{'error'};
}

# ------------------------------------------------------------------------------
sub _validate_value
{
    my ( $self, $name, $value ) = @_;

    if( $self->{'vars'}->{$name}->[0] eq 'I' )
    {
        if(    $value !~ /^[\-\+]?\d+$/
            || $value < $DB7_INT_MIN
            || $value > $DB7_INT_MAX )
        {
            return $self->_e( "Invalid INTEGER value of '$name': $value" );
        }
    }
    else
    {
        my $length = length $value;
        if( $length > $self->{'vars'}->{$name}->[1] )
        {
            return $self->_e( "Too long value for field '$name': $length/"
                    . $self->{'vars'}->{$name}->[1] );
        }
    }

    if( $self->{'vars'}->{$name}->[0] eq 'D' && $value !~ /^\d{8}$/ )
    {
        return $self->_e( "Invalid DATE value for '$name': '$value'" );
    }

    if(    $self->{'vars'}->{$name}->[0] eq 'L'
        && $value !~ /^[TYNF \?]$/i )
    {
        return $self->_e( "Invalid LOGICAL value for '$name': '$value'" );
    }
}

# ------------------------------------------------------------------------------
sub add_record
{
    my ( $self, $data ) = @_;

    return $self->{'error'} if $self->{'error'};

    my %rec;
    foreach my $name ( keys %{ $self->{'vars'} } )
    {
        my $value = $data->{$name};
        if( $value )
        {
            $self->_validate_value( $name, $value ) unless $self->{'nocheck'};
            return $self->{'error'} if $self->{'error'};
        }
        $rec{$name} = $value || '';
    }
    push @{ $self->{'records'} }, \%rec;
    return;
}

# ------------------------------------------------------------------------------
sub write_file
{
    my ( $self ) = @_;

    return $self->{'error'} if $self->{'error'};

    return $self->_e(
        'No fields description given in ' . __PACKAGE__ . '::new()' )
        if( !$self->{'vars'} || !keys %{ $self->{'vars'} } );

    open my $dbf, '>:raw', $self->{'file'}
        or return $self->_e(
        'Can not write "' . $self->{'file'} . '": ' . $ERRNO );
    binmode $dbf;

    return $self->{'error'} if $self->_write_header( $dbf );

    my $field_descr = $DB7_FIELD_DESCR;
    $field_descr =~ s[\s+//.+$][]gm;
    $field_descr =~ s[\s+][]g;

    foreach my $key ( sort keys %{ $self->{'vars'} } )
    {
        print $dbf pack(
            $field_descr,
            $key,
            $self->{'vars'}->{$key}->[0],
            ( $self->{'vars'}->{$key}->[1] & $DB7_CHAR_MAX ),
            (   $self->{'vars'}->{$key}->[0] eq 'C'
                ? ( ( $self->{'vars'}->{$key}->[1] << $DB7_CHAR_BITS )
                    & $DB7_CHAR_MAX )
                : 0 ),
            '' );
    }
    print $dbf pack( 'C', $DB7_HEADER_END );

    foreach my $record ( @{ $self->{'records'} } )
    {
        # 32 - regular record, 42 - deleted record
        print $dbf pack( 'C', 32 );
        foreach my $key ( sort keys %{$record} )
        {
            if( $self->{'vars'}->{$key}->[0] eq 'I' )
            {
                print $dbf pack( 'N', ( $record->{$key} || 0 ) );
            }
            else
            {
                print $dbf pack(
                    'A' . ( $self->{'vars'}->{$key}->[1] ),
                    $record->{$key} );
            }
        }
    }

    print $dbf pack( 'C', $DB7_FILE_END );
    close $dbf;

    return $self->{'error'};
}

# ------------------------------------------------------------------------------
sub _write_header
{
    my ( $self, $dbf ) = @_;

    return $self->{'error'} if $self->{'error'};

    my $header = $DB7_HEADER;
    $header =~ s[\s+//.+$][]gm;
    $header =~ s[\s+][]g;

    my ( undef, undef, undef, $mday, $mon, $year ) = gmtime( time );

    print $dbf pack(
        $header,
        $DB7_SIGNATURE,
        $year, $mon + 1, $mday,
        scalar @{ $self->{'records'} },
        $self->{'header_size'},
        $self->{'record_size'},
        '',
        $DB7_DEF_CODEPAGE,
        0,
        $self->{'language'},
        0 );

    return $self->{'error'};
}

# ------------------------------------------------------------------------------
1;

__END__

=head1 SYNOPSIS

  use DB7;
  my $db7 = new DB7
  (
    {
      file => 'filename.dbf',
      language => 'db866ru0',
      nocheck => 1
    },
    {
      INT_FLD  => [ 'I', 4 ],   # integer field, length = 4
      DATE_FLD => [ 'D' ],      # date field, length always 8
      BOOL_FLD => [ 'L' ],      # bool field, length always 1
      CHAR_FLD => [ 'C', 128 ], # char field, length = 128
    }
  );
  die $db7->errstr if $db7->errstr;

  $db7->add_record
  (
    {
      INT_FLD => 1234,
      DATE_FLD => '20150101',
      BOOL_FLD => 'Y',
      CHAR_FLD => 'Some string'
    }
  );
  die $db7->errstr if $db7->errstr;

  $db7->write_file();
  die $db7->errstr if $db7->errstr;

=head1 DESCRIPTION

This module can write dBase 7 files. MDX (indexes) and MEMO are not supported. 

Known field types: 

B<D> date 
B<I> integer 
B<L> logical 
B<C> character 

=head1 METHODS

=over

=item new( I<$options>, I<$fields> )

Options is hash ref, valid fields are:

B<file> - filename to write, required

B<language> - language driver ID, default is 'DBWINUS0' (ANSI)

B<nocheck> - skip values validation if is set

=item add_record( I<$record> )

Record is hash ref (name => value). Unknown keys are ignored.

=item write_file()

=item errstr()

=back

=head1 AUTHOR

(c) 2015 Vsevolod Lutovinov

All rights reserved. This package is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

Contact the author at klopp@yandex.ru.
