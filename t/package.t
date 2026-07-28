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
    qr{\./perls/upgrade_supported\.pl\s+100644\b},
    'package contains the consolidated upgrade-eligibility plugin'
);
for my $retired (qw(
    bigsur catalina elcapitan goldengate leopard lion mavericks mojave
    monterey mountainlion sequoia sierra snowleopard sonoma tahoe ventura
    yosemite
)) {
    unlike(
        $listing,
        qr{\./perls/\Q$retired\E_upgrade_supported\.pl\b},
        "package excludes the retired $retired-only upgrade plugin"
    );
}
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

sub build_with_env {
    my ($output_path, $env) = @_;
    my $log = "$output_path.build.log";
    my $status;
    {
        local *SAVEERR;
        open(SAVEERR, '>&STDERR') or die "Could not save STDERR: $!";
        open(STDERR, '>', $log) or die "Could not redirect STDERR: $!";

        local $ENV{PATH} = $env->{PATH} if exists $env->{PATH};

        # Always pinned one way or the other, never left to whatever the
        # invoking shell happens to already have set, so these tests exercise
        # exactly the override behavior they claim to and nothing ambient.
        local $ENV{MUNKI_PERLS_ZOPFLI};
        if (exists $env->{MUNKI_PERLS_ZOPFLI}) {
            $ENV{MUNKI_PERLS_ZOPFLI} = $env->{MUNKI_PERLS_ZOPFLI};
        } else {
            delete $ENV{MUNKI_PERLS_ZOPFLI};
        }

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

sub build_with_path {
    my ($output_path, $path) = @_;
    return build_with_env($output_path, { PATH => $path });
}

sub payload_size {
    my ($package_path, $expand_into) = @_;
    my $status = system {
        '/usr/sbin/pkgutil'
    } '/usr/sbin/pkgutil', '--expand', $package_path, $expand_into;
    die "pkgutil could not expand $package_path\n" if $status != 0;
    return (stat("$expand_into/Payload"))[7];
}

sub decompressed_payload {
    my ($package_path, $expand_into) = @_;
    my $status = system {
        '/usr/sbin/pkgutil'
    } '/usr/sbin/pkgutil', '--expand', $package_path, $expand_into;
    return undef if $status != 0;
    open(my $cpio, '-|', '/usr/bin/gzip', '-dc', "$expand_into/Payload")
        or return undef;
    binmode $cpio;
    local $/;
    my $decompressed = <$cpio>;
    # close(), not just a successful read, catches gzip exiting nonzero
    # partway through, which a truncated stream could otherwise still
    # satisfy the content checks below by sheer luck of what came first.
    return undef unless close $cpio;
    return $decompressed;
}

sub payload_matches_source {
    my ($package_path, $expand_into) = @_;
    my $decompressed = decompressed_payload($package_path, $expand_into);
    return 0 unless defined($decompressed) && index($decompressed, 'MunkiPerls') >= 0;
    # A cpio archive's trailer entry is the format's own end-of-archive
    # marker; requiring it catches truncation that lands after the first
    # match above but before the archive actually finished.
    return index($decompressed, 'TRAILER!!!') >= 0;
}

my ($zopfli_path) = grep { -f $_ && -x _ } map {
    File::Spec->catfile($_, 'zopfli')
} File::Spec->path();
my $has_zopfli = defined $zopfli_path;

# The blank MUNKI_PERLS_ZOPFLI override, not just the reduced PATH, is what
# actually makes "zopfli is not installed" deterministic here: a bare PATH
# happens not to contain zopfli on every host this has been tested on, but
# nothing guarantees that in general, and this fallback baseline is reused
# below as the payload-size comparison every other test in this file
# measures against.
my $fallback_package = "$directory/fallback-0.1.43.pkg";
my ($fallback_status, $fallback_log) = build_with_env(
    $fallback_package,
    {
        PATH => '/usr/bin:/usr/sbin:/bin:/sbin',
        MUNKI_PERLS_ZOPFLI => '',
    }
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
    skip 'zopfli is not installed on this host', 4 unless $has_zopfli;

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
    ok(
        payload_matches_source($squeezed_package, "$directory/squeezed-expanded"),
        'squeezed payload decompresses to the real payload contents too'
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

SKIP: {
    # These specifically exercise MUNKI_PERLS_ZOPFLI, the override CI uses
    # to pin its own verified binary instead of letting build-pkg.pl go
    # searching PATH for a substitute. All three need a real zopfli on PATH
    # to be a meaningful test of "the override wins regardless of PATH".
    skip 'zopfli is not installed on this host', 9 unless $has_zopfli;

    my $blank_override_package = "$directory/blank-override-0.1.43.pkg";
    my ($blank_override_status, $blank_override_log) = build_with_env(
        $blank_override_package,
        { PATH => $ENV{PATH}, MUNKI_PERLS_ZOPFLI => '' }
    );
    is($blank_override_status, 0, 'a blank override still builds successfully');
    ok(-f $blank_override_package, 'a blank override still produces a package');
    like(
        $blank_override_log,
        qr/zopfli not found/,
        'a blank override is treated as unavailable even with zopfli on PATH'
    );

    # Test-owned and guaranteed absent, rather than assuming no host ever
    # has anything at a fixed path like /nonexistent/zopfli.
    my $missing_override_path = "$directory/no-such-zopfli";
    my $bogus_override_package = "$directory/bogus-override-0.1.43.pkg";
    my ($bogus_override_status, $bogus_override_log) = build_with_env(
        $bogus_override_package,
        {
            PATH => $ENV{PATH},
            MUNKI_PERLS_ZOPFLI => $missing_override_path,
        }
    );
    is($bogus_override_status, 0, 'a nonexistent override still builds successfully');
    ok(-f $bogus_override_package, 'a nonexistent override still produces a package');
    like(
        $bogus_override_log,
        qr/zopfli not found/,
        'a nonexistent override path does not fall back to a PATH search'
    );

    my $pinned_package = "$directory/pinned-0.1.43.pkg";
    my ($pinned_status, $pinned_log) = build_with_env(
        $pinned_package,
        {
            PATH => '/usr/bin:/usr/sbin:/bin:/sbin',
            MUNKI_PERLS_ZOPFLI => $zopfli_path,
        }
    );
    is($pinned_status, 0, 'a pinned override still builds successfully');
    ok(-f $pinned_package, 'a pinned override still produces a package');
    like(
        $pinned_log,
        qr/zopfli saved \d+ bytes/,
        'an explicit override is used even when PATH alone would find nothing'
    );
}
