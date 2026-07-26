use 5.008006;
use strict;
use warnings;

use Test::More 'no_plan';
use lib 'conditions/lib';
use MunkiPerls::Plugins qw(load_plugin);

my $plugin = load_plugin('conditions/perls/shard.pl');
my $shard = $plugin->{package}->can('shard');
my $shard_for_identifier = $plugin->{package}->can('shard_for_identifier');
die "shard plugin has no collectors\n"
    unless $shard && $shard_for_identifier;

is($shard_for_identifier->('C02TESTSERIAL'), 51, 'serial hash vector matches Salt and Chef');
is($shard_for_identifier->('BUILD123UUT'), 40, 'build-unit hash vector matches Salt and Chef');
is(
    $shard_for_identifier->('12345678-1234-1234-1234-123456789ABC'),
    67,
    'UUID hash vector matches Salt and Chef'
);

is($shard->(
    ioreg_output => qq{
        "IOPlatformUUID" = "12345678-1234-1234-1234-123456789ABC"
        "IOPlatformSerialNumber" = "C02TESTSERIAL"
    },
), 51, 'serial number is preferred over UUID');

is($shard->(
    ioreg_output => qq{
        "IOPlatformUUID" = "12345678-1234-1234-1234-123456789ABC"
    },
), 67, 'UUID is used when serial number is missing');

is($shard->(ioreg_output => ''), 99, 'missing serial and UUID fall back to shard 99');
is($shard->(ioreg_output => 'not ioreg output'), 99, 'malformed ioreg output falls back to shard 99');
is($shard->(ioreg_probe => sub { return (0, '') }), 99, 'failed ioreg probe falls back to shard 99');
