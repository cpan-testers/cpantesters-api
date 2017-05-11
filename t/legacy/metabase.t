
use Mojo::Base '-strict';
use Test::More;
use Test::Mojo;
use FindBin qw( $Bin );
use File::Spec::Functions qw( catfile catdir );
use Mojo::File qw( path );
use DBI;

use Mojo::JSON qw( to_json );

my $SHARE_DIR = path( $Bin, '..', 'share' );
my $bin_path = path( $Bin, '..', '..', 'bin', 'cpantesters-legacy-metabase' );
require $bin_path;
my $t = Test::Mojo->new;

# App is hooked to an in-memory database by config
# (t/etc/metabase.conf), so we must deploy a tablespace
my $schema = $t->app->schema;
$schema->deploy;

subtest 'post report' => sub {
    my $given_report = create_report(
        grade => 'pass',
        distfile => 'PREACTION/Foo-Bar-1.24.tar.gz',
        distribution => 'Foo-Bar-1.24',
        comments => 'Test output',
        from => 'doug@example.com (PREACTION)',
    );
    my $guid = $given_report->core_metadata->{guid};

    $t->post_ok( '/api/v1/submit/CPAN-Testers-Metabase' => json => $given_report->as_struct )
      ->status_is( 201 )
      ->or( sub { diag explain shift->tx->res->body } )
      ->header_is( Location => '/guid/' . $guid )
      ->json_is( { guid => $guid } );

    my $row = $schema->resultset( 'Metabase' )->find( $guid );
    ok $row, 'row found by guid';
    is $row->updated, $given_report->core_metadata->{updated}, 'updated is correct';
};

done_testing;

#sub create_report
#
#   my $report = create_report(
#       grade => 'pass',
#       distfile => 'P/PR/PREACTION/Foo-Bar-1.24.tar.gz',
#       distribution => 'Foo-Bar-1.24',
#       comments => 'Test output',
#       from => 'doug@example.com (PREACTION)',
#   );
#
# Create a new report to submit. Returns a data structure suitable to be
# encoded into JSON and submitted.
#
# This code is stolen from:
#   * Test::Reporter::Transport::Metabase sub send
#   * Metabase::Client::Simple sub submit_fact

sub create_report {
    my $report = Test::Reporter->new( transport => 'Null', @_ );

    # Build CPAN::Testers::Report with its various component facts.
    my $metabase_report = CPAN::Testers::Report->open(
        resource => 'cpan:///distfile/' . $report->distfile
    );

    $metabase_report->add( 'CPAN::Testers::Fact::LegacyReport' => {
        grade => $report->grade,
        osname => 'linux',
        osversion => '2.14.4',
        archname => 'x86_64-linux',
        perl_version => '5.12.0',
        textreport => $report->report
    });

    # TestSummary happens to be the same as content metadata 
    # of LegacyReport for now
    $metabase_report->add( 'CPAN::Testers::Fact::TestSummary' =>
        [$metabase_report->facts]->[0]->content_metadata()
    );

    $metabase_report->close();

    return $metabase_report;
}

