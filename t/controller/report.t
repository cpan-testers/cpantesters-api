
=head1 DESCRIPTION

This file tests the L<CPAN::Testers::API::Controller::Report> controller.

=cut

use CPAN::Testers::API::Base 'Test';
use FindBin ();
use Mojo::File qw( path );
use Mojo::JSON qw( decode_json );
my $SHARE_DIR = path( $FindBin::Bin, '..', 'share' );
my $HEX = qr{[A-Fa-f0-9]};

my $t = prepare_test_app();

subtest '/v3/report' => \&_test_api, '/v3';

sub _test_api( $base ) {
    subtest 'post report' => sub {
        my $report = decode_json( $SHARE_DIR->child( 'perl5.v3.json' )->slurp );
        $t->post_ok( $base . '/report', json => $report )
          ->status_is( 201 )
          ->or( sub { diag shift->tx->res->body } )
          ->json_like( '/id' => qr{${HEX}{8}-${HEX}{4}-${HEX}{4}-${HEX}{4}-${HEX}{12}} )
          ;
    };
}

done_testing;

