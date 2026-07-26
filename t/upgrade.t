use 5.008006;
use strict;
use warnings;

use Test::More 'no_plan';
use lib 'conditions/lib';
use MunkiPerls::Upgrade qw(
    collect_hardware_snapshot evaluate_upgrade_perl evaluate_upgrade_perls
    version_compare
);

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
    sysctl_values => {
        'hw.target' => '',
        'machdep.cpu.features' => 'SSE4 VMM AVX',
    },
);
ok($pre_bigsur_vm->{is_virtual}, 'pre-Big-Sur VMM feature means virtual');

my $pre_bigsur_physical = collect_hardware_snapshot(
    version => '10.15.7',
    ioreg_output => 'not a plist',
    sysctl_values => {
        'hw.target' => '',
        'machdep.cpu.features' => 'SSE4 AVX',
    },
);
ok(!$pre_bigsur_physical->{is_virtual}, 'pre-Big-Sur system without VMM is physical');

my $modern_vm = collect_hardware_snapshot(
    version => '11.0',
    ioreg_output => 'not a plist',
    sysctl_values => {
        'hw.target' => '',
        'kern.hv_vmm_present' => '1',
    },
);
ok($modern_vm->{is_virtual}, 'Big Sur and newer use kern.hv_vmm_present');

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
