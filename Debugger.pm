package Log::Log4perl::Appender::Debugger;

# ------------------------------------------------------------------------------
#  Created on: 22.01.2016, 23:56:05
#  Author: Vsevolod Lutovinov <klopp@yandex.ru>
# ------------------------------------------------------------------------------
use utf8;
use Modern::Perl;
use English qw/-no_match_vars/;

# ------------------------------------------------------------------------------
use Carp;
use File::Basename;
use Log::Any::Proxy;
our @ISA = qw/Log::Log4perl::Appender/;
our $VERSION   = '1.0';

# ------------------------------------------------------------------------------
sub new {
    my ( $class, %options ) = @_;

    my $self = {
        appender => undef,
        %options
    };

    push @{ $options{l4p_depends_on} }, $self->{appender};

    push @{ $options{l4p_post_config_subs} }, sub { $self->post_init() };

    bless $self, $class;

    my $ref           = ref $self;
    my $no_trace_subs = qr/^(Log|$ref)::/;

    my $ExcludeSubsFromTrace;
    $self->{ExcludeSubsFromTrace}
        and $ExcludeSubsFromTrace = qr/$self->{ExcludeSubsFromTrace}/;

    my $ExcludeFilesFromTrace;
    $self->{ExcludeFilesFromTrace}
        and $ExcludeFilesFromTrace = qr/$self->{ExcludeFilesFromTrace}/;

    my $TraceLine = $self->{TraceLine} || '%s at %f, line %l';

    my $FileBasename = $self->{FileBasename};

    Log::Log4perl::Layout::PatternLayout::add_global_cspec(
        'D',
        sub {
            my ( $depth, $tabs, $callers, @callers ) = ( 0, 1, q{} );

            while (1) {
                my ( undef, $file, $line, $sub ) = caller( $depth++ );
                last unless $sub;
                next if $sub =~ /$no_trace_subs/;
                next
                    if $ExcludeSubsFromTrace
                    && $sub =~ /$ExcludeSubsFromTrace/;
                next
                    if $ExcludeFilesFromTrace
                    && $file =~ /$ExcludeFilesFromTrace/;

                $file = basename($file) if $FileBasename;
                my $tline = $TraceLine;
                $tline =~ s/%s/$sub/gs;
                $tline =~ s/%l/$line/gs;
                $tline =~ s/%f/$file/gs;

                unshift @callers, $tline;
            }

            $callers .= ( q{ } x ( $tabs++ ) ) . "$_\n" for @callers;
            return $callers;
        }
    );

    return $self;
}

# ------------------------------------------------------------------------------
sub post_init {
    my ($self) = @_;

    if ( !exists $self->{appender} ) {
        Carp::croak( 'No appender defined for ' . __PACKAGE__ );
    }

    my $appenders = Log::Log4perl->appenders();
    my $appender  = $appenders->{ $self->{appender} };

    if ( !defined $appender ) {
        Carp::croak(
            "Appender $self->{appender} not defined for " . __PACKAGE__ );
    }
    $self->{app} = $appender;

    my $dopt = $self->{DumperOptions} || q{};

    while ($appender) {
        if ( $appender->{appender} && $appender->{appender}->{DumperOptions} ) {
            if ( $self->{MergeDumperOptions} ) {
                $dopt =~ s/,+\s+$//s;
                $dopt .= q{,};
                $dopt .= $appender->{appender}->{DumperOptions};
            }
            else {
                $dopt = $appender->{appender}->{DumperOptions};
            }
        }
        last unless $appender->{appender}->{appender};
        $appender = $appenders->{ $appender->{appender}->{appender} };
    }

    $self->_set_dumper_options($dopt) if $dopt;
}

# ------------------------------------------------------------------------------
sub _set_dumper_options {
    my ( $self, $opt ) = @_;

    eval "use Data::Printer $opt;";

    Carp::croak("Invalid DumperOptions : $opt\n$EVAL_ERROR\n") if $EVAL_ERROR;

    no warnings 'redefine';
    *Log::Any::Proxy::_default_formatter = sub {
        my ( $cat, $lvl, $format, @params ) = @_;
        unshift @params, $format;
        my @new_params
            = map { !defined $_ ? '<?>' : ref $_ ? p($_) : $_ } @params;
        return join "\n", @new_params;
    };
}

# ------------------------------------------------------------------------------
sub log {
    my ( $self, %params ) = @_;

    local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + 2;

    $params{message} = join q{}, @{ $params{message} };

    $self->{app}
        ->SUPER::log( \%params, $params{log4p_category}, $params{log4p_level} );
}

# ------------------------------------------------------------------------------

1;

__END__
