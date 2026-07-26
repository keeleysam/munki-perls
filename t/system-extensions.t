use 5.008006;
use strict;
use warnings;

use File::Temp qw(tempdir);
use Test::More 'no_plan';
use lib 'conditions/lib';
use Foundation;
use MunkiPerls qw(
    foundation_array foundation_dictionary foundation_string write_plist_file
);
use MunkiPerls::Plugins qw(load_plugin);

my $plugin = load_plugin('conditions/perls/system_extensions.pl');
my $system_extensions = $plugin->{package}->can('system_extensions');
die "system_extensions plugin has no collector\n" unless $system_extensions;

sub extension_row {
    my ($state, $identifier) = @_;
    my $row = foundation_dictionary();
    $row->setObject_forKey_(
        foundation_string($state), foundation_string('state')
    ) if defined $state;
    $row->setObject_forKey_(
        foundation_string($identifier), foundation_string('identifier')
    ) if defined $identifier;
    return $row;
}

sub string_array {
    my (@strings) = @_;
    my $array = foundation_array();
    for my $string (@strings) {
        $array->addObject_(foundation_string($string));
    }
    return $array;
}

sub policy_mapping {
    my (%mapping) = @_;
    my $dictionary = foundation_dictionary();
    for my $team_id (keys %mapping) {
        $dictionary->setObject_forKey_(
            string_array(@{$mapping{$team_id}}),
            foundation_string($team_id)
        );
    }
    return $dictionary;
}

my $directory = tempdir(CLEANUP => 1);
my $database_path = "$directory/db.plist";
my $database = foundation_dictionary();
my $extensions = foundation_array();

for my $row (
    extension_row('activated_enabled', 'com.example.zulu'),
    extension_row('activated_enabled', 'com.example.alpha'),
    extension_row('activated_enabled', 'com.example.alpha'),
    extension_row('activated_disabled', 'com.example.disabled'),
    extension_row('activated_waiting_for_user', 'com.example.waiting'),
    extension_row('activated_waiting_for_upgrade', 'com.example.upgrade'),
    extension_row(
        'terminated_waiting_to_uninstall_on_reboot',
        'com.example.uninstalling'
    ),
    extension_row('activated_enabled', ''),
    extension_row('activated_enabled', undef),
    extension_row(undef, 'com.example.missing-state'),
) {
    $extensions->addObject_($row);
}
$extensions->addObject_(foundation_string('malformed row'));
$database->setObject_forKey_($extensions, foundation_string('extensions'));

my $policies = foundation_array();
my $policy = foundation_dictionary();
$policy->setObject_forKey_(
    policy_mapping(
        TEAMA => ['com.example.alpha', 'com.example.alpha'],
        TEAMZ => ['com.example.zulu'],
        TEAMP => ['com.example.policy'],
    ),
    foundation_string('allowedExtensions')
);
$policy->setObject_forKey_(
    policy_mapping(
        TEAMT => ['com.apple.system_extension.endpoint_security'],
    ),
    foundation_string('allowedExtensionTypes')
);
$policy->setObject_forKey_(
    string_array('TEAMONLY'),
    foundation_string('allowedTeamIDs')
);
$policies->addObject_($policy);
$policies->addObject_(foundation_string('malformed policy'));
$database->setObject_forKey_(
    $policies, foundation_string('extensionPolicies')
);
ok(write_plist_file($database_path, $database), 'writes system-extension fixture');

is_deeply(
    [$system_extensions->($database_path)],
    [qw(com.example.alpha com.example.zulu)],
    'returns only sorted, deduplicated, activated and enabled bundle IDs'
);

my $approved_system_extension_policy =
    $plugin->{package}->can('approved_system_extension_policy');
die "system_extensions plugin has no policy collector\n"
    unless $approved_system_extension_policy;
my ($bundle_ids, $team_ids, $approved_extensions) =
    $approved_system_extension_policy->($database_path);
is_deeply(
    $bundle_ids,
    [qw(
        com.example.alpha
        com.example.policy
        com.example.zulu
    )],
    'approved policy bundle IDs are sorted and deduplicated'
);
is_deeply(
    $team_ids,
    [qw(TEAMA TEAMONLY TEAMP TEAMT TEAMZ)],
    'approved policy team IDs are sorted and deduplicated'
);
is_deeply(
    $approved_extensions,
    [qw(
        TEAMA:com.example.alpha
        TEAMP:com.example.policy
        TEAMZ:com.example.zulu
    )],
    'approved policy keys combine team ID and bundle ID'
);

my $missing_path = "$directory/pre-catalina.plist";
is_deeply(
    [$system_extensions->($missing_path)],
    [],
    'a pre-Catalina system without the database returns an empty array'
);
my @missing_policy = $approved_system_extension_policy->($missing_path);
is_deeply(\@missing_policy, [[], [], []], 'missing database returns empty policy arrays');

my $malformed_path = "$directory/malformed.plist";
open(my $malformed, '>', $malformed_path) or die $!;
print {$malformed} 'not a property list';
close $malformed;
is_deeply(
    [$system_extensions->($malformed_path)],
    [],
    'a malformed database returns an empty array'
);

my $wrong_shape_path = "$directory/wrong-shape.plist";
my $wrong_shape = foundation_dictionary();
$wrong_shape->setObject_forKey_(
    foundation_string('not an array'), foundation_string('extensions')
);
ok(write_plist_file($wrong_shape_path, $wrong_shape), 'writes wrong-shape fixture');
is_deeply(
    [$system_extensions->($wrong_shape_path)],
    [],
    'a database without an extensions array returns an empty array'
);
