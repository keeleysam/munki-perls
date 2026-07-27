use 5.008006;
use strict;
use warnings;

use Test::More 'no_plan';
use lib 'conditions/lib';
use MunkiPerls qw(system_profiler_snapshot);

my $calls = 0;
my ($ok, $output) = system_profiler_snapshot(
    runner => sub {
        $calls++;
        return (1, 'first result');
    },
);
is($calls, 1, 'first call invokes the runner');
is($ok, 1, 'first call returns the runner ok status');
is($output, 'first result', 'first call returns the runner output');

my ($second_ok, $second_output) = system_profiler_snapshot(
    runner => sub {
        $calls++;
        return (1, 'second result');
    },
);
is($calls, 1, 'a later call reuses the cached result instead of invoking the runner again');
is($second_ok, 1, 'a later call returns the originally cached ok status');
is($second_output, 'first result', 'a later call returns the originally cached output');
