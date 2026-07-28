use 5.008006;
use strict;
use warnings;

use File::Spec;
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

sub build_with_path {
    my ($output_path, $path) = @_;
    my $log = "$output_path.build.log";
    my $status;
    {
        local *SAVEERR;
        open(SAVEERR, '>&STDERR') or die "Could not save STDERR: $!";
        open(STDERR, '>', $log) or die "Could not redirect STDERR: $!";
        local $ENV{PATH} = $path;
        $status = system {
            $^X
        } $^X, 'tools/build-pkg.pl', '--version', '0.1.43',
            '--output', $output_path, '--verbose';
        open(STDERR, '>&SAVEERR') or die "Could not restore STDERR: $!";
        close SAVEERR;
    }
    open(my $log_fh, '<', $log) or die $!;
    local $/;
    my $log_contents = <$log_fh>;
    close $log_fh;
    return ($status, $log_contents);
}

sub payload_size {
    my ($package_path, $expand_into) = @_;
    my $status = system {
        '/usr/sbin/pkgutil'
    } '/usr/sbin/pkgutil', '--expand', $package_path, $expand_into;
    die "pkgutil could not expand $package_path\n" if $status != 0;
    return (stat("$expand_into/Payload"))[7];
}

sub payload_matches_source {
    my ($package_path, $expand_into) = @_;
    my $status = system {
        '/usr/sbin/pkgutil'
    } '/usr/sbin/pkgutil', '--expand', $package_path, $expand_into;
    return 0 if $status != 0;
    open(my $cpio, '-|', '/usr/bin/gzip', '-dc', "$expand_into/Payload")
        or return 0;
    binmode $cpio;
    local $/;
    my $decompressed = <$cpio>;
    close $cpio;
    return defined($decompressed) && index($decompressed, 'MunkiPerls') >= 0;
}

my $has_zopfli = grep {
    my $candidate = File::Spec->catfile($_, 'zopfli');
    -f $candidate && -x _;
} File::Spec->path();

# Forcing a bare PATH exercises the "zopfli is not installed" fallback
# deterministically, rather than depending on whether the test host
# happens to have it. Every CI runner takes this branch unless zopfli was
# explicitly installed for the release job.
my $fallback_package = "$directory/fallback-0.1.43.pkg";
my ($fallback_status, $fallback_log) = build_with_path(
    $fallback_package, '/usr/bin:/usr/sbin:/bin:/sbin'
);
is($fallback_status, 0, 'package still builds with zopfli unavailable');
like(
    $fallback_log,
    qr/zopfli not found/,
    'missing zopfli is reported, not silently ignored'
);
ok(
    payload_matches_source($fallback_package, "$directory/fallback-expanded"),
    'fallback payload decompresses to the real payload contents'
);

SKIP: {
    skip 'zopfli is not installed on this host', 3 unless $has_zopfli;

    my $squeezed_package = "$directory/squeezed-0.1.43.pkg";
    my ($squeezed_status, $squeezed_log) = build_with_path(
        $squeezed_package, $ENV{PATH}
    );
    is($squeezed_status, 0, 'package builds with zopfli available');
    like(
        $squeezed_log,
        qr/zopfli saved \d+ bytes/,
        'zopfli savings are reported when it runs'
    );

    my $fallback_size = payload_size(
        $fallback_package, "$directory/fallback-payload-check"
    );
    my $squeezed_size = payload_size(
        $squeezed_package, "$directory/squeezed-payload-check"
    );
    cmp_ok(
        $squeezed_size, '<', $fallback_size,
        'zopfli payload is smaller than the plain gzip payload'
    );
}
