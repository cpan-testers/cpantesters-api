package CPAN::Testers::API::Controller::Summary;
our $VERSION = '0.025';
# ABSTRACT: API for test report summary data

=head1 DESCRIPTION

This API accesses the test report summaries, which are a few fields picked out of
the larger test report data structure that are useful for reporting.

=head1 SEE ALSO

=over

=item L<CPAN::Testers::Schema::Result::Stats>

=item L<Mojolicious::Controller>

=back

=cut

use Mojo::Base 'Mojolicious::Controller';
use CPAN::Testers::API::Base;

=method summary

    ### Requests:
    GET /v3/summary/My-Dist
    GET /v3/summary/My-Dist/1.000

    ### Response:
    200 OK
    Content-Type: application/json

    [
        {
            "guid": "00000000-0000-0000-0000-0000000000001",
            "id": 1,
            "grade": "pass",
            "dist": "My-Dist",
            "version": "1.000",
            "tester": "doug@example.com (Doug Bell)",
            "platform": "darwin",
            "perl": "5.22.0",
            "osname": "darwin",
            "osvers": "10.8.0"
        }
    ]

Get test report summary data for the given distribution and version.

Report summary data contains a select set of fields from the full test
report. These fields are the most useful ones for building aggregate
reporting and graphs for dashboards.

=cut

sub summary( $c ) {
    $c->openapi->valid_input or return;

    my $dist = $c->validation->param( 'dist' );
    my $version = $c->validation->param( 'version' );
    my $grade = $c->validation->param( 'grade' );
    my $perl = $c->validation->every_param( 'perl' );
    my $osname = $c->validation->every_param( 'osname' );

    if ( !$dist && !$version && ( !$perl || !@$perl ) && ( !$osname || !@$osname ) ) {
        return $c->render_error( 400, "You must provide one of 'perl' or 'osname'" );
    }

    my $rs = $c->schema->resultset( 'Stats' );
    $rs = $rs->search(
        {
            ( $dist ? ( dist => $dist ) : () ),
            ( $version ? ( version => $version ) : () ),
            ( $perl && @$perl ? ( perl => $perl ) : () ),
            ( $osname && @$osname ? ( osname => $osname ) : () ),
            ( $grade ? ( state => $grade ) : () ),
        },
        {
            columns => [qw( guid fulldate state tester dist version platform perl osname osvers )],
            # Only get hashrefs out
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    if ( my $since = $c->validation->param( 'since' ) ) {
        $rs = $rs->since( $since );
    }

    $c->stream_rs( $rs, sub {
        my $result = shift;
        $result->{grade} = delete $result->{state};
        $result->{date} = _format_date( delete $result->{fulldate} );
        $result->{reporter} = delete $result->{tester};
        return $result;
    } );
}

sub _format_date( $fulldate ) {
    my ( $y, $m, $d, $h, $n ) = $fulldate =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})/;
    return "$y-$m-${d}T$h:$n:00Z";
}

1;
__END__

