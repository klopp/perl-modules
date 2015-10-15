package BindInsert;

# ------------------------------------------------------------------------------
use Modern::Perl;
use DBI;
use Try::Catch;
use File::Temp qw/tempfile/;
use File::Basename qw/basename/;

# ------------------------------------------------------------------------------
sub DESTROY {
    my $self = shift;
    if ( $self->{'data'} ) {
        undef $self->{'data'}->{$_} for keys %{ $self->{'data'} };
        undef $self->{'data'};
    }
    undef $self->{'sth'};
}

# ------------------------------------------------------------------------------
sub new {
    my ( $class, $db ) = @_;
    return bless { 'db' => $db }, $class;
}

# ------------------------------------------------------------------------------
sub db {
    my ( $self, $db ) = @_;
    $self->{'db'} = $db;
}

# ------------------------------------------------------------------------------
sub prepare_insert {
    my ( $self, $table, $columns ) = @_;

    $self->{'error'}    = undef;
    $self->{'data_max'} = 0;

    $self->{'insert'} = "INSERT INTO `$table` (`";
    $self->{'insert'} .= join( '`,`', @{$columns} );
    $self->{'insert'} .= '`) VALUES (';
    $self->{'insert'} .= join( ',', ('?') x ( scalar @{$columns} ) );
    $self->{'insert'} .= ')';

    my $i = 0;
    %{ $self->{'order'} } = map { $_ => $i++ } sort @{$columns};

    my $fields = join( '`,`',
        sort { $self->{'order'}->{$a} <=> $self->{'order'}->{$b} }
            keys %{ $self->{'order'} } );
    $self->{'load'} = "
        LOAD DATA
        INFILE '%s'
        INTO TABLE `$table`
        FIELDS TERMINATED BY ',' ENCLOSED BY '\"'
        (
            `$fields`
        );
    ";

    return $self->{'error'};
}

# ------------------------------------------------------------------------------
sub bind_param_array {
    my ( $self, $data ) = @_;

    $self->bind_param($_) for @{$data};
    return $self->{'data_max'};
}

# ------------------------------------------------------------------------------
sub bind_param {
    my ( $self, $row ) = @_;

    $self->{'data_max'}++;
    while ( my ( $field, $idx ) = each %{ $self->{'order'} } ) {
        push @{ $self->{'data'}->{$idx} },
            defined $row->{$field} ? $row->{$field} : q{};
    }
    return $self->{'data_max'};
}

# ------------------------------------------------------------------------------
sub insert {
    my ( $self, $temppath, $realpath ) = @_;

    $self->{'error'} = undef;

    if ($temppath) {
        my ( $fh, $filename );
        try {
            ( $fh, $filename ) = tempfile( DIR => $temppath );
            my $realfile
                = $realpath
                ? $realpath . '/' . basename($filename)
                : $filename;

            my $kdata = ( keys %{ $self->{'data'} } ) - 1;
            for my $i ( 0 .. ($self->{'data_max'}-1) ) {
                my $line = q{};
                for my $j ( 0 .. $kdata ) {
                    $line .= defined $self->{'data'}->{$j}->[$i]
                        ? $self->{'db'}->quote(
                        $self->{'data'}->{$j}->[$i]
                        )
                        : q{};
                    $line .= q{,};
                }
                $line =~ s/.$/\n/;
                print $fh $line;
            }
            close $fh;
            chmod 0644, $filename;

            my $do = sprintf( $self->{'load'}, $realfile );
            $self->{'db'}->do($do);
        }
        catch {
            $self->{'error'} = $_;
        };

        unlink $filename if $filename;
    }

    else {

        try {
            $self->{'sth'} = $self->{'db'}->prepare( $self->{'insert'} );
            my $idx = 1;
            for ( sort { $a <=> $b } keys %{ $self->{'data'} } ) {
                $self->{'sth'}->bind_param_array( $idx, $self->{'data'}->{$_} );
                $idx++;
            }
            $self->{'sth'}->execute_array( {} );
            undef $self->{'data'}->{$_} for keys %{ $self->{'data'} };
            undef $self->{'data'};
        }
        catch {
            $self->{'error'} = $_;
        };
    }

    $self->{'data_max '} = 0;
    undef $self->{'data'}->{$_} for keys %{ $self->{'data'} };
    undef $self->{'data'};

    return $self->{'error'};
}

# ------------------------------------------------------------------------------
1;

__END__

=pod

=head1 SYNOPSIS

my $insert = BindInsert->new( $dbh );
$insert->prepare_insert( 'table_name', 'field1', 'field2' );

$insert->bind_param( {'field1' => 'value1', 'field2' => 'value2'} );
$insert->bind_param( {'field1' => 'value3', 'field2' => 'value4'} );
$insert->bind_param( {'field1' => 'value5', 'field2' => 'value6'} );

# OR

$insert->bind_param_array
( 
    [
        {'field1' => 'value1', 'field2' => 'value2'},
        {'field1' => 'value3', 'field2' => 'value4'},
        {'field1' => 'value5', 'field2' => 'value6'} 
    ]
);

$insert->insert();

OR

$insert->insert( '/tmp' );

OR

$insert->insert( '/tmp', '/remote/tmp' );

=cut

