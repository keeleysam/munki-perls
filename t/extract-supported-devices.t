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

my $directory = tempdir(CLEANUP => 1);
my $input = "$directory/assets.plist";
my $root = foundation_dictionary();
my $assets = foundation_array();
for my $models (
    ['Mac15,3', 'Mac14,2'],
    ['Mac14,2', 'Mac16,1'],
) {
    my $asset = foundation_dictionary();
    my $supported = foundation_array();
    $supported->addObject_(foundation_string($_)) for @{$models};
    $asset->setObject_forKey_(
        $supported, foundation_string('SupportedDeviceModels')
    );
    $assets->addObject_($asset);
}
$root->setObject_forKey_($assets, foundation_string('Assets'));
ok(write_plist_file($input, $root, 100), 'writes installer fixture with Foundation');

my $tool = 'tools/extract_supported_devices.pl';
open(my $child, '-|', $^X, $tool, '--input', $input) or die $!;
local $/;
my $output = <$child>;
close $child;
is($?, 0, 'extractor succeeds');
is($output, "qw(\n    Mac14,2\n    Mac15,3\n    Mac16,1\n)\n", 'models are validated, deduplicated, and sorted');

my $bad_input = "$directory/bad.plist";
my $bad_root = foundation_array();
write_plist_file($bad_input, $bad_root, 100);
open($child, '-|', $^X, $tool, '--input', $bad_input) or die $!;
while (<$child>) { }
close $child;
isnt($?, 0, 'extractor rejects a non-dictionary root');
