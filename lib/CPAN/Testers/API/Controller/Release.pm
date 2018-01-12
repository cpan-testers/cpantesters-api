package CPAN::Testers::API::Controller::Release;
our $VERSION = '0.023';
# ABSTRACT: API for test reports collected by CPAN release

=head1 DESCRIPTION

This API accesses summary data collected by CPAN release. So, if you
just want to know how many PASS and FAIL reports a single distribution
has for each version released, this is the best API.

=head1 SEE ALSO

=over

=item L<CPAN::Testers::Schema::Result::Release>

=item L<Mojolicious::Controller>

=back

=cut

use Mojo::Base 'Mojolicious::Controller';
use CPAN::Testers::API::Base;

=method release

    ### Requests:
    GET /v3/release
    GET /v3/release/dist/My-Dist
    GET /v3/release/author/PREACTION

    ### Optional query parameters (may be combined):
    # ?since=2016-01-01T12:34:00
    # ?maturity=stable
    # ?limit=2

    ### Response:
    200 OK
    Content-Type: application/json

    [
        {
            "dist": "My-Dist",
            "version": "1.000",
            "pass": 34,
            "fail": 2,
            "na": 1,
            "unknown": 0
        }
    ]

Get release data. Results can be limited by:

=over

=item *

distribution (with the C<dist> key in the stash)

=item *

author (with the C<author> key in the stash)

=item *

date (with the C<since> query parameter)

=item *

maturity (with the C<maturity> query parameter)

=item *

limit (limits the total number of results sent with the C<limit> query parameter)

=back

Release data contains a summary of the pass, fail, na, and unknown test
results created by stable Perls. Development Perls (odd-numbered 5.XX
releases) are not included.

=cut

sub release( $c ) {
    $c->openapi->valid_input or return;

    my $rs = $c->schema->resultset( 'Release' );
    $rs = $rs->search(
        {
            perlmat => 1, # only stable perls
            patched => 1, # not patched perls
        },
        {
            columns => [qw( dist version pass fail na unknown )],
            # Only get hashrefs out
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    # Only allow "since" for "dist" and "author" because the query can
    # not be optimized to return in a reasonable time.
    if ( my $since = $c->param( 'since' ) ) {
        unless ( $c->validation->param( 'dist' ) || $c->validation->param( 'author' ) ) {
            return $c->render_error( 400 => '"since" parameter not allowed' );
        }
        $rs = $rs->since( $since );
    }

    if ( my $maturity = $c->param( 'maturity' ) ) {
        $rs = $rs->maturity( $maturity );
    }

    my @results;
    my $limit = $c->param( 'limit' );
    # OpenAPI spec doesn't support property "minimum" on parameters
    if ( $limit and $limit < 1 ) {
        return $c->render_error( 400 => 'The value for "limit" must be a positive integer' );
    }

    if ( my $dist = $c->validation->param( 'dist' ) ) {
        $rs = $rs->by_dist( $dist );
        @results = $limit ? $rs->slice( 0, $limit - 1 ) : $rs->all;
        if ( !@results ) {
            return $c->render_error( 404, sprintf 'Distribution "%s" not found', $dist );
        }
    }
    elsif ( my $author = $c->validation->param( 'author' ) ) {
        $rs = $rs->by_author( $author );
        @results = $limit ? $rs->slice( 0, $limit - 1 ) : $rs->all;
        if ( !@results ) {
            return $c->render_error( 404, sprintf 'Author "%s" not found', $author );
        }
    }
    else {
        @results = $limit ? $rs->slice( 0, $limit - 1 ) : $rs->all;
    }

    return $c->render(
        openapi => \@results,
    );
}

1;
__END__

