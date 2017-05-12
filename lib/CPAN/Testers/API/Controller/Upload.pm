package CPAN::Testers::API::Controller::Upload;
our $VERSION = '0.009';
# ABSTRACT: API for uploads to CPAN

=head1 DESCRIPTION

=head1 SEE ALSO

=over

=item L<CPAN::Testers::Schema::Result::Upload>

=item L<Mojolicious::Controller>

=back

=cut

use Mojo::Base 'Mojolicious::Controller';
use CPAN::Testers::API::Base;
use Mojo::UserAgent;

=method get

    ### Requests:
    GET /v1/upload
    GET /v1/upload?since=2016-01-01T12:34:00Z
    GET /v1/upload/dist/My-Dist
    GET /v1/upload/dist/My-Dist?since=2016-01-01T12:34:00Z
    GET /v1/upload/author/PREACTION
    GET /v1/upload/author/PREACTION?since=2016-01-01T12:34:00Z

    ### Response:
    200 OK
    Content-Type: application/json

    [
        {
            "dist": "My-Dist",
            "version": "1.000",
            "author": "PREACTION",
            "filename": "My-Dist-1.000.tar.gz",
            "released": "2016-08-12T04:02:34Z",
        }
    ]

Get CPAN upload data. Results can be limited by distribution (with the
C<dist> key in the stash), by author (with the C<author> key in the
stash), and by date (with the C<since> query parameter).

=cut

sub get( $c ) {
    $c->openapi->valid_input or return;

    my $rs = $c->schema->resultset( 'Upload' );
    $rs = $rs->search(
        { },
        {
            order_by => 'released',
            columns => [qw( dist version author filename released )],
        }
    );

    if ( my $since = $c->param( 'since' ) ) {
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

    my @formatted = map { +{
        dist => $_->dist,
        version => $_->version,
        author => $_->author,
        filename => $_->filename,
        released => $_->released . "",
    } } @results;

    return $c->render(
        openapi => \@formatted,
    );
}

=method feed

Get a feed for uploads to CPAN. This feed returns the same information as
the regular API, but as they come in.

=cut

sub feed( $c ) {
    $c->inactivity_timeout( 60000 );
    my $path = $c->stash( 'dist' ) ? '/upload/dist/' . $c->stash( 'dist' )
             : $c->stash( 'author' ) ? '/upload/author/' . $c->stash( 'author' )
             : '/upload/dist' # Default to all dists
             ;

    my $ua = Mojo::UserAgent->new( inactivity_timeout => 6000 );
    $ua->websocket(
        $c->app->config->{broker} . '/sub' . $path,
        sub( $ua, $tx ) {
            $c->stash( tx => $tx );
            $tx->on(finish => sub( $tx, $code ) {
                # Broker closed connection, so close connection with
                # client, unless that's what we're already doing
                $c->finish if !$c->stash( 'finished' );
            });

            $tx->on( message => sub( $tx, $msg ) {
                $c->send( $msg );
            } );
        }
    );

    $c->stash( ua => $ua );
    $c->on( finish => sub( $c, $tx ) {
        # Client closed connection, so close connection with broker
        if ( my $tx = $c->stash( 'tx' ) ) {
            $c->stash( finished => 1 );
            $tx->finish;
        }
    } );
    $c->rendered( 101 );
}

1;
