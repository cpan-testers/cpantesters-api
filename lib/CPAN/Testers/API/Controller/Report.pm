package CPAN::Testers::API::Controller::Report;
our $VERSION = '0.030';
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

    # First try to get the report from the collector
    if (my $collector_url = $c->app->config->{collector}) {
      my $res;
      local $@;
      eval {
        $res = $c->ua->get("$collector_url/v1/report/$id")->result;
      };
      if (my $e = $@) {
        $c->log->error( sprintf 'Error fetching from collector: %s', $e );
        # XXX: Retry
      }
      elsif ($res->is_success) {
        $c->log->debug( 'Found report in collector' );
        $c->res->headers->content_type('application/json');
        return $c->render(
          format => 'json',
          data => $res->body,
        )
      }
    }

    # Then try the old database
    my $rs = $c->schema->resultset( 'TestReport' );
    my $row = $rs->find($id);
    if ( $row ) {
      $c->log->debug( 'Found report in test_reports' );
      return $c->render(
          openapi => $row->report,
      );
    }

    # Last try the old-old database.
    my $mb_row;
    eval {
      $mb_row = $c->schema->storage->dbh->selectrow_hashref(
        'SELECT * from metabase.metabase WHERE guid=?', {}, $id,
      );
    };
    if ($mb_row) {
      $c->log->debug( 'Found report in metabase' );
      my $report;
      eval {
        my $metabase_report = $rs->parse_metabase_report( $mb_row );
        my $test_report_row = $rs->convert_metabase_report( $metabase_report );
        $report = $test_report_row->{report};
      };
      if (my $e = $@) {
        $c->log->error( sprintf 'Error parsing metabase report %s: %s', $id, $e );
      }
      elsif ($report) {
        return $c->render(json => $report);
      }
    }

    # Nowhere to be found :(
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

1;
