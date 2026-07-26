use 5.008006;
use strict;
use warnings;

use Test::More 'no_plan';
use lib 'conditions/lib';
use MunkiPerls::Upgrade qw(
    collect_hardware_snapshot evaluate_upgrade_perl evaluate_upgrade_perls
    version_compare
);

# Exercised directly against _physical_supported via a synthetic release,
# not through the real @RELEASES table - these test the matcher dispatch
# itself, independent of any real release's data. A leading underscore is
# just a naming convention in Perl, not access control, so a fully
# qualified call works with no special syntax needed.
ok(MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'model', values => { 'iMac14,1' => 1 } } ] },
    { model => 'iMac14,1' },
), 'model condition matches when snapshot model is in values');
ok(!MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'model', values => { 'iMac14,1' => 1 } } ] },
    { model => 'iMac15,1' },
), 'model condition rejects when snapshot model is not in values');

ok(MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'hardware_target', values => { 'J293AP' => 1 } } ] },
    { hardware_target => 'J293AP' },
), 'hardware_target condition matches when snapshot target is in values');
ok(!MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'hardware_target', values => { 'J293AP' => 1 } } ] },
    { hardware_target => '' },
), 'hardware_target condition rejects an empty snapshot target');

ok(MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'cpu', cpu_type => 'intel' } ] },
    { cpu_type => 'intel', cpu_family => '', cpu_64bit => 0, cpu_frequency_mhz => 0 },
), 'cpu condition with only cpu_type matches any speed or family');
ok(!MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'cpu', cpu_type => 'intel' } ] },
    { cpu_type => 'powerpc', cpu_family => 'g5', cpu_64bit => 0, cpu_frequency_mhz => 2000 },
), 'cpu condition rejects a different cpu_type');
ok(MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'cpu', cpu_type => 'powerpc', cpu_family => 'g4', min_frequency_mhz => 867 } ] },
    { cpu_type => 'powerpc', cpu_family => 'g4', cpu_64bit => 0, cpu_frequency_mhz => 867 },
), 'cpu condition min_frequency_mhz matches at the exact boundary');
ok(!MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'cpu', cpu_type => 'powerpc', cpu_family => 'g4', min_frequency_mhz => 867 } ] },
    { cpu_type => 'powerpc', cpu_family => 'g4', cpu_64bit => 0, cpu_frequency_mhz => 800 },
), 'cpu condition rejects below min_frequency_mhz');
ok(MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'cpu', cpu_type => 'powerpc', cpu_family => 'g5' } ] },
    { cpu_type => 'powerpc', cpu_family => 'g5', cpu_64bit => 0, cpu_frequency_mhz => 2000 },
), 'cpu condition with no min_frequency_mhz matches any speed for that family');
ok(MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'cpu', cpu_type => 'intel', cpu_64bit => 1 } ] },
    { cpu_type => 'intel', cpu_family => '', cpu_64bit => 1, cpu_frequency_mhz => 2000 },
), 'cpu condition cpu_64bit matches a 64-bit-capable snapshot');
ok(!MunkiPerls::Upgrade::_physical_supported(
    { allow => [ { type => 'cpu', cpu_type => 'intel', cpu_64bit => 1 } ] },
    { cpu_type => 'intel', cpu_family => '', cpu_64bit => 0, cpu_frequency_mhz => 2000 },
), 'cpu condition cpu_64bit rejects a 32-bit-only snapshot');

ok(MunkiPerls::Upgrade::_physical_supported(
    {
        allow => [
            { type => 'model', values => { 'MacPro5,1' => 1 } },
            { all => [
                { type => 'model', values => { 'Mac16,7' => 1 } },
                { type => 'cpu', cpu_type => 'intel' },
            ] },
        ],
    },
    { model => 'MacPro5,1', cpu_type => 'powerpc' },
), 'allow list OR: matches via the first entry even though the second would fail');
ok(MunkiPerls::Upgrade::_physical_supported(
    {
        allow => [
            { type => 'model', values => { 'MacPro5,1' => 1 } },
            { all => [
                { type => 'model', values => { 'Mac16,7' => 1 } },
                { type => 'cpu', cpu_type => 'intel' },
            ] },
        ],
    },
    { model => 'Mac16,7', cpu_type => 'intel' },
), 'allow list OR: matches via the second (all-composite) entry even though the first would fail');
ok(!MunkiPerls::Upgrade::_physical_supported(
    {
        allow => [
            { all => [
                { type => 'model', values => { 'Mac16,7' => 1 } },
                { type => 'cpu', cpu_type => 'intel' },
            ] },
        ],
    },
    { model => 'Mac16,7', cpu_type => 'powerpc' },
), 'all composite: model matches but cpu does not, so the whole condition fails');

my $survived = eval {
    MunkiPerls::Upgrade::_physical_supported(
        { allow => [ { type => 'nonsense' } ] },
        {},
    );
    1;
};
ok($survived, 'unknown condition type does not crash the process');

sub perls {
    my (%overrides) = @_;
    return evaluate_upgrade_perls({
        version => '10.13.6',
        model => 'MacBookPro9,1',
        board_id => 'Mac-06F11F11946D27C5',
        hardware_target => '',
        is_virtual => 0,
        %overrides,
    });
}

is(version_compare('10.15.7', '11'), -1, '10.15 sorts below 11');
is(version_compare('26.0', '16'), 1, 'Tahoe major 26 is not treated as 16');

ok(perls(version => '10.7')->{sierra_upgrade_supported}, 'Sierra lower boundary supported');
ok(perls(version => '10.11.6')->{sierra_upgrade_supported}, 'Sierra upper source boundary supported');
ok(!perls(version => '10.6.8', is_virtual => 1)->{sierra_upgrade_supported}, 'Sierra rejects below minimum before VM');
ok(!perls(version => '10.12', is_virtual => 1)->{sierra_upgrade_supported}, 'Sierra rejects already-upgraded VM');
ok(!perls(version => '10.13')->{sierra_upgrade_supported}, 'Sierra rejects systems above target');
ok(perls(
    version => '10.11.6', model => 'unsupported',
    board_id => 'unsupported', is_virtual => 1,
)->{sierra_upgrade_supported}, 'Sierra permits an eligible VM');
ok(!perls(model => 'MacBookPro5,1')->{sierra_upgrade_supported}, 'Sierra rejects original blocked model');
ok(!perls(board_id => 'unsupported')->{sierra_upgrade_supported}, 'Sierra requires original board table');
ok(perls(
    version => '10.11.6', model => 'MacBookPro9,1',
    board_id => 'Mac-4B7AC7E43945597E',
)->{sierra_upgrade_supported}, 'Sierra accepts supported model and board combination');

ok(perls(version => '10.7')->{mojave_upgrade_supported}, 'Mojave lower boundary supported');
ok(perls(version => '10.13.6')->{mojave_upgrade_supported}, 'Mojave upper source boundary supported');
ok(!perls(version => '10.6.8', is_virtual => 1)->{mojave_upgrade_supported}, 'Mojave rejects below minimum before VM');
ok(!perls(version => '10.14', is_virtual => 1)->{mojave_upgrade_supported}, 'Mojave rejects already-upgraded VM');
ok(!perls(model => 'MacBookPro8,2')->{mojave_upgrade_supported}, 'Mojave rejects original blocked model');
ok(!perls(board_id => 'unsupported')->{mojave_upgrade_supported}, 'Mojave requires original board table');

ok(!perls(version => '10.8.5', is_virtual => 1)->{catalina_upgrade_supported}, 'Catalina rejects below minimum before VM');
ok(perls(version => '10.9', is_virtual => 1)->{catalina_upgrade_supported}, 'Catalina lower boundary VM supported');
ok(perls(version => '10.14.6')->{catalina_upgrade_supported}, 'Catalina upper source boundary supported');
ok(!perls(version => '10.15', is_virtual => 1)->{catalina_upgrade_supported}, 'Catalina rejects already-upgraded VM');
ok(!perls(version => '10.14', model => 'MacPro5,1')->{catalina_upgrade_supported}, 'Catalina rejects original blocked model');

ok(perls(version => '10.15', model => 'MacBook8,1')->{bigsur_upgrade_supported}, 'Big Sur supported model retained');
ok(!perls(version => '11', is_virtual => 1)->{bigsur_upgrade_supported}, 'Big Sur rejects already-upgraded VM');
ok(perls(version => '11', model => 'iMacPro1,1')->{monterey_upgrade_supported}, 'Monterey includes iMacPro1,1');

ok(perls(version => '14', model => 'MacBookPro16,3')->{sequoia_upgrade_supported}, 'Sequoia retains MacBookPro16,3');
ok(!perls(version => '15', model => 'MacBookPro16,3')->{tahoe_upgrade_supported}, 'Tahoe excludes MacBookPro16,3');
ok(perls(version => '15', model => 'MacBookPro16,4')->{tahoe_upgrade_supported}, 'Tahoe includes neighboring supported model');
ok(!perls(version => '26', model => 'MacBookPro16,4', is_virtual => 1)->{tahoe_upgrade_supported}, 'Tahoe major 26 is already upgraded');

ok(perls(version => '26', hardware_target => 'J180dAP')->{goldengate_upgrade_supported}, 'Goldengate hardware target supported');
ok(!perls(version => '27', hardware_target => 'J180dAP', is_virtual => 1)->{goldengate_upgrade_supported}, 'Goldengate rejects target-version VM');

for my $boundary (
    ['sierra_upgrade_supported', '10.11', '10.12'],
    ['bigsur_upgrade_supported', '10.15', '11'],
    ['monterey_upgrade_supported', '11', '12'],
    ['ventura_upgrade_supported', '12', '13'],
    ['sonoma_upgrade_supported', '13', '14'],
    ['sequoia_upgrade_supported', '14', '15'],
    ['tahoe_upgrade_supported', '15', '26'],
    ['goldengate_upgrade_supported', '26', '27'],
) {
    my ($key, $below, $target) = @{$boundary};
    ok(perls(version => $below, is_virtual => 1)->{$key}, "$key permits an eligible VM below target");
    ok(!perls(version => $target, is_virtual => 1)->{$key}, "$key rejects a VM at target");
}

my $pre_bigsur_vm = collect_hardware_snapshot(
    version => '10.15.7',
    ioreg_output => 'not a plist',
    profiler_output => 'not a plist',
    sysctl_values => {
        'hw.target' => '',
        'machdep.cpu.features' => 'SSE4 VMM AVX',
    },
);
ok($pre_bigsur_vm->{is_virtual}, 'pre-Big-Sur VMM feature means virtual');

my $pre_bigsur_physical = collect_hardware_snapshot(
    version => '10.15.7',
    ioreg_output => 'not a plist',
    profiler_output => 'not a plist',
    sysctl_values => {
        'hw.target' => '',
        'machdep.cpu.features' => 'SSE4 AVX',
    },
);
ok(!$pre_bigsur_physical->{is_virtual}, 'pre-Big-Sur system without VMM is physical');

my $modern_vm = collect_hardware_snapshot(
    version => '11.0',
    ioreg_output => 'not a plist',
    profiler_output => 'not a plist',
    sysctl_values => {
        'hw.target' => '',
        'kern.hv_vmm_present' => '1',
    },
);
ok($modern_vm->{is_virtual}, 'Big Sur and newer use kern.hv_vmm_present');

my $board_id_fixture = qq{<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>board-id</key>
        <string>Mac-FAKE0000000001</string>
    </dict>
</array>
</plist>};

# Shaped like the real, shared system_profiler_snapshot() result: an array
# with one entry per requested data type, including one (config profiles)
# that never has the key we want. Proves the recursive search finds
# machine_model regardless of which other entries are present.
my $profiler_fixture = qq{<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>_dataType</key>
        <string>SPConfigurationProfileDataType</string>
    </dict>
    <dict>
        <key>_dataType</key>
        <string>SPHardwareDataType</string>
        <key>_items</key>
        <array>
            <dict>
                <key>_name</key>
                <string>hardware_overview</string>
                <key>machine_model</key>
                <string>Mac99,9</string>
            </dict>
        </array>
    </dict>
</array>
</plist>};

my $ioreg_calls = 0;
my $tiger_snapshot = collect_hardware_snapshot(
    version => '10.4.11',
    ioreg_probe => sub { $ioreg_calls++; return (1, $board_id_fixture) },
    profiler_output => $profiler_fixture,
    sysctl_values => { 'hw.target' => '', 'machdep.cpu.features' => '' },
);
is($ioreg_calls, 0, 'ioreg -a is never invoked below Leopard');
is($tiger_snapshot->{model}, 'Mac99,9', 'pre-Leopard hardware identity model comes from system_profiler');
is($tiger_snapshot->{board_id}, '', 'pre-Leopard hardware identity board_id is empty');

$ioreg_calls = 0;
my $leopard_snapshot = collect_hardware_snapshot(
    version => '10.5.8',
    ioreg_probe => sub { $ioreg_calls++; return (1, $board_id_fixture) },
    profiler_output => $profiler_fixture,
    sysctl_values => { 'hw.target' => '', 'machdep.cpu.features' => '' },
);
is($ioreg_calls, 1, 'ioreg -a is invoked once on Leopard and newer');
is($leopard_snapshot->{model}, 'Mac99,9', 'Leopard and newer hardware identity model comes from system_profiler');
is($leopard_snapshot->{board_id}, 'Mac-FAKE0000000001', 'Leopard and newer hardware identity board_id is parsed from ioreg');

is(scalar(keys %{perls()}), 10, 'consolidated evaluator emits ten upgrade perls');

for my $snapshot (
    {
        version => '10.13.6', model => 'MacBookPro9,1',
        board_id => 'Mac-06F11F11946D27C5', hardware_target => '',
        is_virtual => 0,
    },
    {
        version => '14', model => 'unsupported', board_id => 'unsupported',
        hardware_target => 'unsupported', is_virtual => 1,
    },
    {
        version => '26', model => 'MacBookPro16,4', board_id => '',
        hardware_target => 'J180dAP', is_virtual => 0,
    },
) {
    my $aggregate = evaluate_upgrade_perls($snapshot);
    for my $key (sort keys %{$aggregate}) {
        is(
            evaluate_upgrade_perl($key, $snapshot),
            $aggregate->{$key},
            "$key single-perl evaluation matches aggregate compatibility API"
        );
    }
}

my $unknown = eval {
    evaluate_upgrade_perl('unknown_upgrade_supported', {
        version => '14', is_virtual => 1,
    });
    1;
};
ok(!$unknown, 'single-perl evaluator rejects unknown keys');
