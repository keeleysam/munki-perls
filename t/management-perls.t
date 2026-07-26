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

sub plugin_function {
    my ($name, $function) = @_;
    my $plugin = load_plugin("conditions/perls/$name.pl");
    my $callback = $plugin->{package}->can($function);
    die "$name does not define $function\n" unless $callback;
    return $callback;
}

sub plist_bytes {
    my ($path) = @_;
    open(my $fh, '<', $path) or die $!;
    binmode $fh;
    local $/;
    my $bytes = <$fh>;
    close $fh;
    return $bytes;
}

my $client_id = plugin_function('client_id', 'client_id');
my $mdm_install = plugin_function('mdm_install', 'mdm_install');

my $domain = foundation_dictionary();
$domain->setObject_forKey_(
    foundation_string('canary'), foundation_string('ClientIdentifier')
);
is($client_id->(domain => $domain), 'canary', 'client_id reads Munki ClientIdentifier');
is($client_id->(domain => foundation_dictionary()), '', 'missing ClientIdentifier returns an empty string');

my $directory = tempdir(CLEANUP => 1);
my $profile_root = foundation_array();

my $non_mdm_profile = foundation_dictionary();
$non_mdm_profile->setObject_forKey_(
    NSDate->dateWithTimeIntervalSince1970_(1000),
    foundation_string('profileInstallDate')
);
$non_mdm_profile->setObject_forKey_(
    foundation_string('com.apple.wifi.managed'),
    foundation_string('PayloadType')
);
$profile_root->addObject_($non_mdm_profile);

my $mdm_profile = foundation_dictionary();
$mdm_profile->setObject_forKey_(
    NSDate->dateWithTimeIntervalSince1970_(3600),
    foundation_string('profileInstallDate')
);
my $payloads = foundation_array();
my $mdm_payload = foundation_dictionary();
$mdm_payload->setObject_forKey_(
    foundation_string('com.apple.mdm'),
    foundation_string('PayloadType')
);
$payloads->addObject_($mdm_payload);
$mdm_profile->setObject_forKey_($payloads, foundation_string('_items'));
$profile_root->addObject_($mdm_profile);

my $profile_path = "$directory/profiles.plist";
ok(write_plist_file($profile_path, $profile_root, 100), 'writes MDM profile fixture');

my ($install_date, $hours_since_install) = $mdm_install->(
    profile_output => plist_bytes($profile_path),
    now => 3600 + 25 * 3600 + 1,
);
is($install_date, '1970-01-01T01:00:00Z', 'MDM install date is formatted in UTC');
is($hours_since_install, 25, 'MDM hours since install is floored to whole hours');

($install_date, $hours_since_install) = $mdm_install->(
    profile_output => plist_bytes($profile_path),
    now => 0,
);
is($hours_since_install, 0, 'future MDM install dates do not return negative hours');

($install_date, $hours_since_install) = $mdm_install->(
    profile_output => '<not plist>',
);
is($install_date, '', 'malformed profile output returns an empty MDM install date');
is($hours_since_install, 0, 'malformed profile output returns zero MDM install hours');

my $offset_root = foundation_array();
my $offset_profile = foundation_dictionary();
$offset_profile->setObject_forKey_(
    foundation_string('1970-01-01 02:00:00 +0200'),
    foundation_string('profileInstallDate')
);
my $offset_payloads = foundation_array();
$offset_payloads->addObject_($mdm_payload);
$offset_profile->setObject_forKey_($offset_payloads, foundation_string('_items'));
$offset_root->addObject_($offset_profile);
my $offset_path = "$directory/offset-profiles.plist";
ok(write_plist_file($offset_path, $offset_root, 100), 'writes offset-date MDM profile fixture');

($install_date, $hours_since_install) = $mdm_install->(
    profile_output => plist_bytes($offset_path),
    now => 3600,
);
is($install_date, '1970-01-01T00:00:00Z', 'string MDM install dates honor timezone offsets');
