use 5.008006;
use strict;
use warnings;

use File::Basename qw(basename);
use File::Temp qw(tempdir);
use Scalar::Util qw(blessed);
use Test::More 'no_plan';
use lib 'conditions/lib';
use Foundation;
use MunkiPerls qw(foundation_string load_plist_file objc_string);
use MunkiPerls::Plugins qw(run_plugins_condition);

my @executables = grep { -x $_ } sort glob('conditions/*.pl');
is_deeply(
    [map { basename($_) } @executables],
    ['munki_perls.pl'],
    'the discovery runner is the only top-level condition executable'
);

my @plugins = sort glob('conditions/perls/*.pl');
ok(@plugins, 'bundled plugins are installed');
for my $plugin (@plugins) {
    ok(!-x $plugin, "$plugin is not executable");
}

my $directory = tempdir(CLEANUP => 1);
my $output = "$directory/ConditionalItems.plist";
my $status = run_plugins_condition(
    ['--output', $output],
    plugin_dir => 'conditions/perls',
    preference_loader => sub { return {} },
    config_path => "$directory/missing-config.plist",
);
is($status, 0, 'the discovery runner collects bundled plugins');

my $plist = load_plist_file($output, dictionary => 1);
ok(blessed($plist) && $$plist, 'runner output is a dictionary plist');

my %arrays = map { $_ => 1 } qw(
    admin_users approved_system_extension_bundle_ids
    approved_system_extension_team_ids approved_system_extensions
    local_user_dirs system_extensions
);
my %strings = map { $_ => 1 } qw(
    client_id console_user crashplan_username filevault_status
    gatekeeper_status highest_supported_macos_version mdm_install_date
    mdm_managed_user physical_or_virtual sip_status virtual_type
);
my %integers = map { $_ => 1 } qw(
    mdm_hours_since_install shard
);
my @bundled_keys = sort qw(
    admin_users
    approved_system_extension_bundle_ids
    approved_system_extension_team_ids
    approved_system_extensions
    backtomymac_configured
    client_id
    console_user
    console_user_logged_in
    crashplan_username
    filevault_status
    gatekeeper_status
    highest_supported_macos_version
    latest_macos_supported
    local_user_dirs
    mdm_hours_since_install
    mdm_install_date
    mdm_managed_user
    physical_or_virtual
    shard
    sip_status
    system_extensions
    virtual_type
);

ok(
    do {
        my $machine_type = $plist->objectForKey_(
            foundation_string('machine_type')
        );
        !blessed($machine_type) || !$$machine_type;
    },
    'runner does not emit machine_type'
);

for my $key (@bundled_keys) {
    my $value = $plist->objectForKey_(foundation_string($key));
    ok(blessed($value) && $$value, "$key is present");
    if ($arrays{$key}) {
        ok($value->isKindOfClass_(NSArray->class()), "$key is an array");
        my $items = $value->objectEnumerator();
        while (my $item = $items->nextObject()) {
            last unless blessed($item) && $$item;
            ok(
                $item->isKindOfClass_(NSString->class()),
                "$key item is a string"
            );
        }
    } elsif ($strings{$key}) {
        ok($value->isKindOfClass_(NSString->class()), "$key is a string");
    } elsif ($integers{$key}) {
        ok($value->isKindOfClass_(NSNumber->class()), "$key is a number");
        isnt($value->objCType(), 'c', "$key is not a plist boolean");
    } else {
        ok($value->isKindOfClass_(NSNumber->class()), "$key is a number");
        is($value->objCType(), 'c', "$key is specifically a plist boolean");
    }
}

for my $key (qw(
    bigsur_upgrade_supported catalina_upgrade_supported elcapitan_upgrade_supported
    goldengate_upgrade_supported leopard_upgrade_supported lion_upgrade_supported
    mavericks_upgrade_supported
    mojave_upgrade_supported monterey_upgrade_supported mountainlion_upgrade_supported
    sequoia_upgrade_supported sierra_upgrade_supported snowleopard_upgrade_supported
    sonoma_upgrade_supported
    tahoe_upgrade_supported ventura_upgrade_supported yosemite_upgrade_supported
)) {
    my $value = $plist->objectForKey_(foundation_string($key));
    next unless blessed($value) && $$value;
    ok($value->isKindOfClass_(NSNumber->class()), "$key, if present, is a number");
}

my $only_output = "$directory/VirtualType.plist";
$status = system {
    $^X
} $^X, 'conditions/munki_perls.pl', '--only', 'virtual_type',
    '--output', $only_output;
is($status, 0, '--only virtual_type selects the bundled plugin');

my $only_plist = load_plist_file($only_output, dictionary => 1);
# virtual_type.pl also contributes physical_or_virtual, since the two are
# the same underlying hardware-snapshot check reported at two granularities.
is($only_plist->count(), 2, '--only virtual_type writes both of its keys');
my $only_value = $only_plist->objectForKey_(
    foundation_string('virtual_type')
);
ok(
    blessed($only_value) && $$only_value
        && $only_value->isKindOfClass_(NSString->class()),
    '--only virtual_type writes a string'
);
my $only_sibling_value = $only_plist->objectForKey_(
    foundation_string('physical_or_virtual')
);
ok(
    blessed($only_sibling_value) && $$only_sibling_value
        && $only_sibling_value->isKindOfClass_(NSString->class()),
    '--only virtual_type also writes its sibling key physical_or_virtual'
);
