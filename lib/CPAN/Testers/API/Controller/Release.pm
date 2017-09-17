package CPAN::Testers::API::Controller::Release;
our $VERSION = '0.019';
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
    GET /v1/release
    GET /v1/release?since=2016-01-01T12:34:00Z
    GET /v1/release/dist/My-Dist
    GET /v1/release/dist/My-Dist?since=2016-01-01T12:34:00Z
    GET /v1/release/author/PREACTION
    GET /v1/release/author/PREACTION?since=2016-01-01T12:34:00Z

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

Get release data. Results can be limited by distribution (with the
C<dist> key in the stash), by author (with the C<author> key in the
stash), and by date (with the C<since> query parameter).

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

    my @results;
    if ( my $dist = $c->validation->param( 'dist' ) ) {
        $rs = $rs->by_dist( $dist );
        @results = $rs->all;
        if ( !@results ) {
            return $c->render_error( 404, sprintf 'Distribution "%s" not found', $dist );
        }
    }
    elsif ( my $author = $c->validation->param( 'author' ) ) {
        @results = $rs->by_author( $author )->all;
        if ( !@results ) {
            return $c->render_error( 404, sprintf 'Author "%s" not found', $author );
        }
    }
    else {
        @results = $rs->all;
    }

    return $c->render(
        openapi => \@results,
    );
}

1;
__END__

