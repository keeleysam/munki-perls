use 5.008006;
use strict;
use warnings;

use File::Temp qw(tempdir);
use Test::More;

if (!-x '/usr/bin/pkgbuild') {
    plan skip_all => '/usr/bin/pkgbuild is required to build packages';
}
plan 'no_plan';

my $directory = tempdir(CLEANUP => 1);
my $package = "$directory/munki-perls-0.1.42.pkg";
my $status = system {
    $^X
} $^X, 'tools/build-pkg.pl', '--version', '0.1.42', '--output', $package;
is($status, 0, 'package builds');
ok(-f $package, 'unsigned package file exists');

my $expanded = "$directory/expanded";
$status = system {
    '/usr/sbin/pkgutil'
} '/usr/sbin/pkgutil', '--expand', $package, $expanded;
is($status, 0, 'pkgutil expands package');

open(my $info, '<', "$expanded/PackageInfo") or die $!;
local $/;
my $package_info = <$info>;
close $info;
like($package_info, qr{identifier="com\.github\.weswhet\.munki-perls"}, 'package identifier is correct');
like($package_info, qr{version="0\.1\.42"}, 'configured package version is correct');
like($package_info, qr{install-location="/usr/local/munki/conditions"}, 'install location is correct');

open(my $bom, '-|', '/usr/bin/lsbom', "$expanded/Bom") or die $!;
my $listing = <$bom>;
close $bom;
is($?, 0, 'lsbom inspects package');
my @executables = $listing =~ /^\.\/([^\.][^\/]*\.pl)\s+100755\b/gm;
is_deeply(
    \@executables,
    ['munki_perls.pl'],
    'package contains one top-level discovery runner'
);
like(
    $listing,
    qr{\./perls/system_extensions\.pl\s+100644\b},
    'package contains non-executable system-extension inventory plugin'
);
like(
    $listing,
    qr{\./perls/virtual_type\.pl\s+100644\b},
    'package contains non-executable virtual-type plugin'
);
unlike(
    $listing,
    qr{\./perls/machine_type\.pl},
    'package excludes retired machine-type plugin'
);
like(
    $listing,
    qr{\./perls/sierra_upgrade_supported\.pl\s+100644\b},
    'package contains non-executable split upgrade plugins'
);
unlike($listing, qr{\./system_extensions\.pl}, 'legacy top-level plugins are absent');
unlike($listing, qr{\./macos_upgrade_supported\.pl}, 'package excludes removed aggregate upgrade condition');
like($listing, qr{\./lib/MunkiPerls\.pm}, 'package contains shared Foundation runtime');
like(
    $listing,
    qr{\./lib/MunkiPerls/Plugins\.pm\s+100644\b},
    'package contains the plugin runtime'
);
unlike(
    $listing,
    qr{\./perls/config\.plist\b},
    'package does not contain a default plugin configuration'
);

ok(
    !-e "$expanded/Scripts/postinstall",
    'package contains no postinstall script'
);
