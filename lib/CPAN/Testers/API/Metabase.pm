package CPAN::Testers::API::Metabase;

use Mojo::Base -strict, -signatures;
use CPAN::Testers::Schema;
use Metabase::Fact;
use Metabase::User::Profile;
use Metabase::User::Secret;
use CPAN::Testers::Report;
use Log::Any::Adapter Multiplex =>
  # Set up Log::Any to log to OpenTelemetry and Stderr so we can still
  # see the local logs.
  adapters => {
    'OpenTelemetry' => [],
    'Stderr' => [
      log_level => $ENV{LOG_LEVEL} || $ENV{MOJO_LOG_LEVEL} || "debug",
    ],
  },
  ;
use Log::Any qw($LOG);

sub write_report($config, $fact_struct) {
  state $schema;
  if (!$schema) {
    local $@;
    eval {
      $schema = CPAN::Testers::Schema->connect( $config->{db}->@{qw( dsn user pass args )} );
    };
    if (my $e = $@) {
      die $LOG->error('Error opening database connection', {error => $e});
    }
  }
  my $row;
  local $@;
  eval {
    my $fact = Metabase::Fact->from_struct($fact_struct);
    $row = $schema->resultset( 'TestReport' )->insert_metabase_fact($fact);
  };
  if (my $e = $@) {
    die $LOG->error('Error writing report to database', {error => $e, guid => $fact_struct->{guid}});
  }
  return {$row->get_columns};
}

1;
