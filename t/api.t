
use CPAN::Testers::API::Base 'Test';
use CPAN::Testers::API;

my $schema = prepare_temp_schema;
my $app = CPAN::Testers::API->new(
    schema => $schema,
);
my $t = Test::Mojo->new( $app );

subtest 'can get OpenAPI document' => sub {
    $t->get_ok( '/v1' )
        ->status_is( 200 )
        ->header_like( 'Content-Type' => qr{^application/json} );
};

done_testing;
