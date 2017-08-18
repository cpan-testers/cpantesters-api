package CPAN::Testers::API::Controller::Summary;
our $VERSION = '0.017';
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

    my $rs = $c->schema->resultset( 'Stats' );
    $rs = $rs->search(
        {
            dist => $dist,
            version => $version,
        },
        {
            columns => [qw( guid fulldate state tester dist version platform perl osname osvers )],
            # Only get hashrefs out
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    my @results = $rs->all;
    if ( !@results ) {
        return $c->render_error( 404, sprintf 'No results found for dist "%s" version "%s"', $dist, $version );
    }

    for my $result ( @results ) {
        $result->{grade} = delete $result->{state};
        $result->{date} = _format_date( delete $result->{fulldate} );
        $result->{reporter} = delete $result->{tester};
    }

    return $c->render(
        openapi => \@results,
    );
}

sub _format_date( $fulldate ) {
    my ( $y, $m, $d, $h, $n ) = $fulldate =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})/;
    return "$y-$m-${d}T$h:$n:00Z";
}

1;
__END__

