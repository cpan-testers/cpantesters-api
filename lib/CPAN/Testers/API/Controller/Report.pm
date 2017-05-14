package CPAN::Testers::API::Controller::Report;
our $VERSION = '0.012';
# ABSTRACT: Work with raw test reports

=head1 DESCRIPTION

This API allows working directly with the JSON report documents
submitted by the army of testers of CPAN.

=head1 SEE ALSO

L<CPAN::Testers::Schema::Result::TestReport>, L<Mojolicious::Controller>

=cut

use Mojo::Base 'Mojolicious::Controller';
use CPAN::Testers::API::Base;

=method report_post

    ### Requests:
    POST /v3/report
    { ... }

    ### Response:
    201 Created
    { "id": "..." }

Submit a new CPAN Testers report. This is used by testers when they're
finished running a test.

=cut

sub report_post( $c ) {
    $c->app->log->debug( 'Submitting Report: ' . $c->req->body );
    $c->openapi->valid_input or return;
    my $report = $c->validation->param( 'report' );
    my $row = $c->schema->resultset( 'TestReport' )->create( {
        report => $report,
    } );
    return $c->render(
        status => 201,
        openapi => {
            id => $row->id,
        },
    );
}

=method report_get

    ### Requests:
    GET /v3/report/:guid

    ### Response
    200 OK
    { "id": "...", ... }

Get a single CPAN Testers report from the database.

=cut

sub report_get( $c ) {
    $c->openapi->valid_input or return;
    my $id = $c->validation->param( 'id' );
    my $row = $c->schema->resultset( 'TestReport' )->find( $id );
    if ( !$row ) {
        return $c->render(
            status => 404,
            openapi => {
                errors => [
                    {
                        message => 'Report ID not found',
                        path => '/id',
                    },
                ],
            },
        );
    }
    return $c->render(
        openapi => $row->report,
    );
}

1;
