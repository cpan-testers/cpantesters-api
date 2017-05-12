package CPAN::Testers::API::Controller::Report;
our $VERSION = '0.007';
# ABSTRACT: Work with raw test reports

=head1 DESCRIPTION

This API allows working directly with the JSON report documents
submitted by the army of testers of CPAN.

=head1 SEE ALSO

L<CPAN::Testers::Schema::Result::TestReport>, L<Mojolicious::Controller>

=cut

use Mojo::Base 'Mojolicious::Controller';
use CPAN::Testers::API::Base;
use Mojo::JSON qw( encode_json );
use Data::UUID;

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
    $c->openapi->valid_input or return;
    my $report = $c->validation->param( 'report' );
    $report->{id} = Data::UUID->new->create_str();
    $c->schema->resultset( 'TestReport' )->create( {
        id => $report->{id},
        report => encode_json( $report ),
    } );
    return $c->render(
        status => 201,
        openapi => {
            id => $report->{id},
        },
    );
}

1;
