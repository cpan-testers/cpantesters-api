package CPAN::Testers::API;
our $VERSION = '0.002';
# ABSTRACT: REST API for CPAN Testers data

=head1 SYNOPSIS

    $ cpantesters-api daemon
    Listening on http://*:5000

=head1 DESCRIPTION

This is a REST API on to the data contained in the CPAN Testers
database. This data includes test reports, CPAN distributions, and
various aggregate test reporting.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Plugin::OpenAPI>,
L<CPAN::Testers::Schema>,
L<http://github.com/cpan-testers/cpantesters-project>,
L<http://www.cpantesters.org>

=cut

use Mojo::Base 'Mojolicious';
use CPAN::Testers::API::Base;
use File::Share qw( dist_file );
use Log::Any::Adapter;

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
    $app->plugin( OpenAPI => {
        url => dist_file( 'CPAN-Testers-API' => 'api.json' ),
        allow_invalid_ref => 1,
    } );
    $app->helper( schema => sub { shift->app->schema } );
    Log::Any::Adapter->set( 'MojoLog', logger => $app->log );
}

1;
__END__
