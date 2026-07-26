use 5.008006;
use strict;
use warnings;

use Test::More 'no_plan';
use lib 'conditions/lib';
use Foundation;
use MunkiPerls qw(
    foundation_array foundation_dictionary foundation_string objc_string
    serialize_plist
);
use MunkiPerls::Plugins qw(load_plugin);

my $virtual_plugin = load_plugin('conditions/perls/virtual_type.pl');
my $physical_plugin = load_plugin('conditions/perls/physical_or_virtual.pl');
my $virtual_type = $virtual_plugin->{package}->can('virtual_type');
my $physical_or_virtual =
    $physical_plugin->{package}->can('physical_or_virtual');
die "virtualization plugins are missing collectors\n"
    unless $virtual_type && $physical_or_virtual;

sub profiler_fixture {
    my (%values) = @_;
    my $root = foundation_array();

    my $ethernet_group = foundation_dictionary();
    my $ethernet_items = foundation_array();
    my $ethernet = foundation_dictionary();
    $ethernet->setObject_forKey_(
        foundation_string($values{ethernet_vendor}),
        foundation_string('spethernet_vendor-id')
    ) if defined $values{ethernet_vendor};
    $ethernet_items->addObject_($ethernet);
    $ethernet_group->setObject_forKey_(
        $ethernet_items, foundation_string('_items')
    );
    $root->addObject_($ethernet_group);

    my $hardware_group = foundation_dictionary();
    my $hardware_items = foundation_array();
    my $hardware = foundation_dictionary();
    $hardware->setObject_forKey_(
        foundation_string($values{boot_rom}),
        foundation_string('boot_rom_version')
    ) if defined $values{boot_rom};
    $hardware_items->addObject_($hardware);
    $hardware_group->setObject_forKey_(
        $hardware_items, foundation_string('_items')
    );
    $root->addObject_($hardware_group);

    my $data = serialize_plist($root, 100);
    my $string = NSString->alloc()->initWithData_encoding_($data, 4);
    return objc_string($string);
}

my $physical_probe_count = 0;
my $physical = $virtual_type->(
    hardware_snapshot => { is_virtual => 0 },
    profiler_probe => sub {
        $physical_probe_count++;
        return (1, profiler_fixture(boot_rom => 'VMW'));
    },
);
is($physical, '', 'physical virtual type is empty');
is($physical_probe_count, 0, 'physical systems do not invoke system_profiler');
is(
    $physical_or_virtual->({ is_virtual => 0 }),
    'physical',
    'physical_or_virtual returns physical independently'
);

my @classifications = (
    ['vmware', profiler_fixture(boot_rom => 'VMW71.00V.21100432.B64.2201181744')],
    ['virtualbox', profiler_fixture(boot_rom => 'VirtualBox')],
    ['parallels', profiler_fixture(ethernet_vendor => 'vendor-id: 0x1ab8')],
    ['parallels', profiler_fixture(ethernet_vendor => '0X1AF4')],
    ['unknown', profiler_fixture(boot_rom => 'Other', ethernet_vendor => '0x1234')],
    ['unknown', 'not a property list'],
);

for my $case (@classifications) {
    my ($expected, $fixture) = @{$case};
    my $probe_count = 0;
    my $type = $virtual_type->(
        hardware_snapshot => { is_virtual => 1 },
        profiler_probe => sub {
            $probe_count++;
            return (1, $fixture);
        },
    );
    is($type, $expected, "$expected virtual machine is classified");
    is($probe_count, 1, "$expected classification uses one profiler probe");
}

my $failed = $virtual_type->(
    hardware_snapshot => { is_virtual => 1 },
    profiler_probe => sub { return (0, '') },
);
is($failed, 'unknown', 'failed profiler output has unknown virtual type');

is(
    $virtual_type->(
        hardware_snapshot => { is_virtual => 1 },
        profiler_output => profiler_fixture(boot_rom => 'VMW'),
    ),
    'vmware',
    'virtual_type accepts injected profiler output'
);

is(
    $physical_or_virtual->({ is_virtual => 1 }),
    'virtual',
    'physical_or_virtual returns virtual independently'
);
