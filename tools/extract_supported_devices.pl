#!/usr/bin/perl
use 5.008006;
use strict;
use warnings;

use FindBin;
use Getopt::Long qw(GetOptions);
use Scalar::Util qw(blessed);
use lib "$FindBin::Bin/../conditions/lib";
use Foundation;
use MunkiPerls qw(foundation_string load_plist_file objc_string);

my $default = '/Volumes/Shared Support/com_apple_MobileAsset_MacSoftwareUpdate/'
    . 'com_apple_MobileAsset_MacSoftwareUpdate.xml';
my $input = $default;
my $help = 0;
GetOptions('input=s' => \$input, 'help' => \$help) or usage(2);
usage(0) if $help;

my $root = load_plist_file($input, dictionary => 1);
die "Unable to read a dictionary property list\n"
    unless blessed($root) && $$root;
my $assets = $root->objectForKey_(foundation_string('Assets'));
die "Assets must be an array\n"
    unless blessed($assets) && $$assets
        && $assets->isKindOfClass_(NSArray->class());

my %models;
my $asset_iterator = $assets->objectEnumerator();
while (my $asset = $asset_iterator->nextObject()) {
    last unless blessed($asset) && $$asset;
    die "Every asset must be a dictionary\n"
        unless $asset->isKindOfClass_(NSDictionary->class());
    my $supported = $asset->objectForKey_(
        foundation_string('SupportedDeviceModels')
    );
    die "SupportedDeviceModels must be an array\n"
        unless blessed($supported) && $$supported
            && $supported->isKindOfClass_(NSArray->class());
    my $model_iterator = $supported->objectEnumerator();
    while (my $model_object = $model_iterator->nextObject()) {
        last unless blessed($model_object) && $$model_object;
        die "Every supported device model must be a string\n"
            unless $model_object->isKindOfClass_(NSString->class());
        my $model = objc_string($model_object);
        die "Supported device models may not be empty or contain whitespace\n"
            unless length($model) && $model !~ /\s/;
        $models{$model} = 1;
    }
}

die "No supported device models were found\n" unless keys %models;
# Installer assets are allowed to be indecisive about ordering.
print "qw(\n";
print "    $_\n" for sort keys %models;
print ")\n";
exit 0;

sub usage {
    my ($status) = @_;
    print "Usage: $0 [--input PATH] [--help]\n";
    exit $status;
}
