package CPAN::Testers::API;
our $VERSION = '0.030';
# ABSTRACT: REST API for CPAN Testers data

=head1 SYNOPSIS

    $ cpantesters-api daemon
    Listening on http://*:5000

=head1 DESCRIPTION

This is a REST API on to the data contained in the CPAN Testers
database. This data includes test reports, CPAN distributions, and
various aggregate test reporting.

=head1 CONFIG

This application can be configured by setting the C<MOJO_CONFIG>
environment variable to the path to a configuration file. The
configuration file is a Perl script containing a single hash reference,
like:

    # api.conf
    {
        broker => 'ws://127.0.0.1:5000',
        schema => 'dbi:SQLite:api.db',
    }

The possible configuration keys are below:

=over

=item broker

The URL to a L<Mercury> message broker, starting with C<ws://>. This
broker is used to forward messages to every connected user.

=item schema

The DBI connect string to give to L<CPAN::Testers::Schema>. If not specified,
will use L<CPAN::Testers::Schema/connect_from_config>.

=back

=head1 LOCAL TESTING

To run an instance of this for local testing, create an C<api.conf> file
to configure a SQLite schema:

    # api.conf
    {
        schema => 'dbi:SQLite:api.sqlite3'
    }

For the L<CPAN::Testers::Schema> to work with SQLite, you will need to
install an additional CPAN module, L<DateTime::Format::SQLite>.

Once this is configured, you can deploy a new, blank database using
C<< cpantesters-api eval 'app->schema->deploy' >>.

Now you can run the API using C<< cpantesters-api daemon >>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Plugin::OpenAPI>,
L<CPAN::Testers::Schema>,
L<http://github.com/cpan-testers/cpantesters-project>,
L<http://www.cpantesters.org>

=cut

use Mojo::Base 'Mojolicious';
use CPAN::Testers::API::Base;
use Scalar::Util qw( blessed );
use File::Share qw( dist_dir dist_file );
use Log::Any::Adapter;
use Alien::SwaggerUI;
use File::Spec::Functions qw( catdir catfile );
use JSON::MaybeXS qw( encode_json );

=method schema

    my $schema = $c->schema;

Get the schema, a L<CPAN::Testers::Schema> object. By default, the
schema is connected from the local user's config. See
L<CPAN::Testers::Schema/connect_from_config> for details.

=cut

has schema => sub {
    my ( $app ) = @_;
    require CPAN::Testers::Schema;
    if ( $app->config->{schema} ) {
        return CPAN::Testers::Schema->connect( $app->config->{schema} );
    }
    return CPAN::Testers::Schema->connect_from_config;
};

=method startup

    # Called automatically by Mojolicious

This method starts up the application, loads any plugins, sets up routes,
and registers helpers.

=cut

sub startup ( $app ) {
    $app->log( Mojo::Log->new ); # Log only to STDERR
    unshift @{ $app->renderer->paths },
        catdir( dist_dir( 'CPAN-Testers-API' ), 'templates' );
    unshift @{ $app->static->paths },
        catdir( dist_dir( 'CPAN-Testers-API' ), 'public' );

    $app->moniker( 'api' );
    $app->plugin( Config => {
        default => { }, # Allow living without config file
    } );

    # Allow CORS for everyone
    $app->hook( after_build_tx => sub {
        my ( $tx, $app ) = @_;
        $tx->res->headers->header( 'Access-Control-Allow-Origin' => '*' );
        $tx->res->headers->header( 'Access-Control-Allow-Methods' => 'GET, POST, PUT, PATCH, DELETE, OPTIONS' );
        $tx->res->headers->header( 'Access-Control-Max-Age' => 3600 );
        $tx->res->headers->header( 'Access-Control-Allow-Headers' => 'Content-Type, X-Requested-With' );
    } );

    my $r = $app->routes;
    $r->get( '/' => 'index' );
    $r->get( '/docs/*docpath' => { docpath => 'index.html' } )->to(
        cb => sub {
            my ( $c ) = @_;
            # Redirect so that trailing / helps browser build URLs and
            # we have our spec loaded. Can't make its own route because
            # the trailing `/` is optional in the Mojolicious route
            # since we declared a default `docpath`. Must pass in
            # a Mojo::URL object to redirect_to() so that the trailing
            # slash is maintained.
            if ( !$c->req->url->path->trailing_slash && $c->req->url->path eq '/docs' ) {
                $c->req->url->path->trailing_slash(1);
                $c->req->url->query( url => '/v3' );
                return $c->redirect_to( $c->req->url );
            }
            my $path = catfile( Alien::SwaggerUI->root_dir, $c->stash( 'docpath' ) );
            my $file = Mojo::Asset::File->new( path => $path );
            $c->reply->asset( $file );
        },
    );

    $r->websocket( '/v1/upload' )->to( 'Upload#feed' );
    $r->websocket( '/v1/upload/dist/:dist' )->to( 'Upload#feed' );
    $r->websocket( '/v1/upload/author/:author' )->to( 'Upload#feed' );

    $r->websocket( '/v3/upload' )->to( 'Upload#feed' );
    $r->websocket( '/v3/upload/dist/:dist' )->to( 'Upload#feed' );
    $r->websocket( '/v3/upload/author/:author' )->to( 'Upload#feed' );

    my $render_fast_json = sub( $c, $data ) {
        if ( blessed $data || ( ref $data eq 'HASH' && $data->{errors} ) ) {
            return Mojo::JSON::encode_json( $data );
        }
        return encode_json( $data );
    };

    $app->plugin( OpenAPI => {
        url => dist_file( 'CPAN-Testers-API' => 'v1.json' ),
        allow_invalid_ref => 1,
        renderer => $render_fast_json,
    } );
    $app->plugin( OpenAPI => {
        url => dist_file( 'CPAN-Testers-API' => 'v3.json' ),
        allow_invalid_ref => 1,
        renderer => $render_fast_json,
    } );
    $app->helper( schema => sub { shift->app->schema } );
    $app->helper( render_error => \&render_error );
    $app->helper( stream_rs => \&stream_rs );

    Log::Any::Adapter->set( 'MojoLog', logger => $app->log );
}

=method render_error

    return $c->render_error( 400 => 'Bad Request' );
    return $c->render_error( 400, {
        path => '/since',
        message => 'Invalid date/time',
    } );

Render an error in JSON like other OpenAPI errors. The first argument
is the HTTP status code. The remaining arguments are a list of errors
to report. Plain strings are turned into one-element hashrefs with a
C<message> key. Hashrefs are used as-is.

The resulting JSON looks like so:

    {
        "errors":  [
            {
                "path": "/",
                "message": "Bad Request"
            }
        ]
    }

    {
        "errors":  [
            {
                "path": "/since",
                "message": "Invalid date/time"
            }
        ]
    }

=cut

sub render_error( $c, $status, @errors ) {
    return $c->render(
        status => $status,
        openapi => {
            errors => [
                map { !ref $_ ? { message => $_, path => '/' } : $_ } @errors,
            ],
        },
    );
}

=method stream_rs

    $c->stream_rs( $rs, $processor );

Stream a L<DBIx::Class::ResultSet> object to the browser. This prevents
problems with proxy servers and CDNs timing out waiting for data. This
uses L<Mojolicious::Controller/write_chunk> to transfer a chunked
response. If there are no results in the ResultSet object, this method
returns a 404 error.

C<$processor> is an optional subref that allows for processing each row
before it is written. Use this to translate column names or values into
the format the API expects.

For this to work usefully behind Fastly, we also need to enable streaming
miss so that Fastly streams the data to the end-user as it gets it:
L<https://docs.fastly.com/guides/performance-tuning/improving-caching-performance-with-large-files#streaming-miss>.

=cut

sub stream_rs {
    my ( $c, $rs, $process ) = @_;
    $process //= sub { shift };
    my $wrote_open = 0;
    my $written = 0;
    my @to_write;

    my $flush_write = sub {
        my $leading_comma = ',';
        if ( !$wrote_open ) {
            $c->write_chunk( '[' );
            $wrote_open = 1;
            $leading_comma = '';
        }
        my $to_write = join ",", map { encode_json( $process->( $_ ) ) } @to_write;
        $c->write_chunk( $leading_comma . $to_write );
        $written += @to_write;
        @to_write = ();
    };

    while ( my $row = $rs->next ) {
        push @to_write, $row;
        if ( @to_write >= 5 ) {
            $flush_write->();
        }
    }
    if ( !$written && !@to_write ) {
        return $c->render_error( 404, 'No results found' );
    }
    if ( @to_write ) {
        $flush_write->();
    }
    return $c->write_chunk( ']', sub { shift->finish } );
}

1;
__END__
