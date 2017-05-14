package CPAN::Testers::API;
our $VERSION = '0.012';
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
    }

The possible configuration keys are below:

=head2 broker

The URL to a L<Mercury> message broker, starting with C<ws://>. This
broker is used to forward messages to every connected user.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Plugin::OpenAPI>,
L<CPAN::Testers::Schema>,
L<http://github.com/cpan-testers/cpantesters-project>,
L<http://www.cpantesters.org>

=cut

use Mojo::Base 'Mojolicious';
use CPAN::Testers::API::Base;
use File::Share qw( dist_dir dist_file );
use Log::Any::Adapter;
use Alien::SwaggerUI;
use File::Spec::Functions qw( catdir catfile );

=method schema

    my $schema = $c->schema;

Get the schema, a L<CPAN::Testers::Schema> object. By default, the
schema is connected from the local user's config. See
L<CPAN::Testers::Schema/connect_from_config> for details.

=cut

has schema => sub {
    require CPAN::Testers::Schema;
    return CPAN::Testers::Schema->connect_from_config;
};

=method startup

    # Called automatically by Mojolicious

This method starts up the application, loads any plugins, sets up routes,
and registers helpers.

=cut

sub startup ( $app ) {
    unshift @{ $app->renderer->paths },
        catdir( dist_dir( 'CPAN-Testers-API' ), 'templates' );
    unshift @{ $app->static->paths },
        catdir( dist_dir( 'CPAN-Testers-API' ), 'public' );

    $app->moniker( 'api' );
    $app->plugin( Config => {
        default => { }, # Allow living without config file
    } );

    my $r = $app->routes;
    $r->get( '/' => 'index' );
    $r->get( '/docs/*path' => { path => 'index.html' } )->to(
        cb => sub {
            my ( $c ) = @_;
            my $path = catfile( Alien::SwaggerUI->root_dir, $c->stash( 'path' ) );
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

    $app->plugin( OpenAPI => {
        url => dist_file( 'CPAN-Testers-API' => 'v1.json' ),
        allow_invalid_ref => 1,
    } );
    $app->plugin( OpenAPI => {
        url => dist_file( 'CPAN-Testers-API' => 'v3.json' ),
        allow_invalid_ref => 1,
    } );
    $app->helper( schema => sub { shift->app->schema } );
    $app->helper( render_error => \&render_error );

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

1;
__END__
