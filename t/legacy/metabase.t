
use Mojo::Base '-strict';
use Test::More;
use Test::Mojo;
use FindBin qw( $Bin );
use File::Spec::Functions qw( catfile catdir );
use Mojo::File qw( path );
use DBI;

use Mojo::JSON qw( to_json );
use Test::Reporter;
use CPAN::Testers::Report;
use CPAN::Testers::Fact::LegacyReport;
use CPAN::Testers::Fact::TestSummary;
use Data::FlexSerializer;

my $dbh = DBI->connect( 'dbi:SQLite::memory:' );
$dbh->do('CREATE TABLE metabase (
    `guid` char(36) NOT NULL,
    `id` int(10),
    `updated` varchar(32),
    `report` longblob,
    `fact` longblob,
    PRIMARY KEY (`guid`)
)');

my $SHARE_DIR = path( $Bin, '..', 'share' );
my $bin_path = path( $Bin, '..', '..', 'bin', 'cpantesters-legacy-metabase' );
require $bin_path;
my $t = Test::Mojo->new;
$t->app->dbh( $dbh );

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

    my ( $row ) = $dbh->selectall_array( 'SELECT * FROM metabase', { Slice => {} } );
    is $row->{guid}, $guid, 'guid is correct';

    my $got_report = parse_report( $row );
    is $got_report->{updated}, $given_report->core_metadata->{updated}, 'updated is correct';

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

#sub parse_report
#
# This sub undoes the processing that CPAN Testers expects before it is
# put in the database so we can ensure that the report was submitted
# correctly.
#
# This code is stolen from:
#   * CPAN::Testers::Data::Generator sub load_fact
sub parse_report {
    my ( $row ) = @_;
    my %report;

    my $sereal_zipper = Data::FlexSerializer->new(
        detect_compression  => 1,
        detect_sereal       => 1,
        output_format       => 'sereal'
    );
    $report{ fact } = $sereal_zipper->deserialize( $row->{fact} );

    my $json_zipper = Data::FlexSerializer->new(
        detect_compression  => 1,
        detect_json         => 1,
        output_format       => 'json'
    );
    $report{ report } = $json_zipper->deserialize( $row->{report} );

    return \%report;
}

