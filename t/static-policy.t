use 5.008006;
use strict;
use warnings;

use File::Find;
use Test::More 'no_plan';
use lib 'conditions/lib';
use MunkiPerls::Perls ();

is_deeply(
    [sort @MunkiPerls::Perls::EXPORT_OK],
    [qw(command_status console_user_perls)],
    'shared perls module exports only multi-perl helpers'
);

my $retired_term = join('', qw(f a c t));
my $approved_upstream_name = 'munki-' . $retired_term . 's';
my @project_files;

# git is required to know the exact tracked-file set (so leftover build
# output and other untracked cruft never end up scanned or missed); on a
# machine without git this whole block is skipped rather than crashing.
my $git_ok = eval {
    open(my $tracked, '-|', 'git', 'ls-files', '-z') or die "$!\n";
    local $/ = "\0";
    while (my $file = <$tracked>) {
        $file =~ s/\0\z//;
        push @project_files, $file if length($file) && -f $file;
    }
    close($tracked) or die "git ls-files failed\n";
    1;
};

SKIP: {
    skip 'git is required to list tracked files', 1 unless $git_ok;

    for my $file (sort @project_files) {
        unlike($file, qr/$retired_term/i, "$file avoids retired terminology");

        open(my $fh, '<', $file) or die $!;
        binmode $fh;
        local $/;
        my $source = <$fh>;
        close $fh;
        next if index($source, "\0") >= 0;

        while ($source =~ /$retired_term/ig) {
            my $start = $-[0];
            my $candidate = $start >= 6
                ? substr($source, $start - 6, length($approved_upstream_name))
                : '';
            my $after = $start >= 6
                ? substr(
                    $source,
                    $start - 6 + length($approved_upstream_name),
                    1
                )
                : '';
            my $approved = $file eq 'README.md'
                && lc($candidate) eq $approved_upstream_name
                && $after !~ /[A-Za-z0-9_-]/;
            if (!$approved && $file eq '.github/workflows/pages.yml') {
                my $line_start = rindex($source, "\n", $start) + 1;
                my $line_end = index($source, "\n", $start);
                $line_end = length($source) if $line_end < 0;
                my $line = substr($source, $line_start, $line_end - $line_start);
                $approved = $line =~ m{actions/upload-pages-arti$retired_term\@v4};
            }
            ok($approved, "$file uses only the approved upstream project name");
        }
    }
}

my @files;
find(
    sub {
        push @files, $File::Find::name
            if -f $_ && /\.(?:pl|pm)\z/;
    },
    'conditions', 'tools'
);

my %approved = map { $_ => 1 } qw(
    /usr/bin/csrutil
    /usr/bin/dscl
    /usr/bin/fdesetup
    /usr/bin/gzip
    /usr/bin/pkgbuild
    /usr/bin/productsign
    /usr/sbin/ioreg
    /usr/sbin/pkgutil
    /usr/sbin/scutil
    /usr/sbin/spctl
    /usr/sbin/sysctl
    /usr/sbin/system_profiler
);

for my $file (sort @files) {
    open(my $fh, '<', $file) or die $!;
    local $/;
    my $source = <$fh>;
    close $fh;

    unlike($source, qr{/(?:usr/)?(?:bin|sbin)/(?:plutil|defaults|osascript)\b}, "$file has no forbidden plist executable");
    unlike($source, qr{PlistBuddy|JSON}, "$file has no forbidden plist helper or conversion");
    unlike($source, qr/`|\bqx\s*[\x2f({]/, "$file has no shell command interpolation");
    unlike($source, qr{\|\s*(?:awk|cut|grep|head|sed)\b}, "$file has no shell pipeline");

    while ($source =~ m{['"](/usr/(?:bin|sbin)/[A-Za-z0-9_.-]+)['"]}g) {
        ok($approved{$1}, "$file subprocess path $1 is allowlisted");
    }
    if ($file ne 'tools/build-pkg.pl'
            && $file ne 'conditions/lib/MunkiPerls.pm') {
        unlike($source, qr{\bsystem\s*(?:\{|\()|\bexec\s*(?:\{|\()}, "$file does not invoke subprocesses outside the shared direct runner");
    }
}
