#!/usr/bin/perl
use 5.008006;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(basename dirname);
use File::Compare qw(compare);
use File::Find;
use File::Path qw(mkpath);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Getopt::Long qw(GetOptions);

my $name = 'munki-perls';
my $identifier = 'com.github.weswhet.munki-perls';
my $version = '0.1.0';
my $install_location = '/usr/local/munki/conditions';
my $output;
my $sign;
my $verbose = 0;
my $help = 0;
GetOptions(
    'version=s' => \$version,
    'output=s' => \$output,
    'sign=s' => \$sign,
    'verbose' => \$verbose,
    'help' => \$help,
) or usage(2);
usage(0) if $help;
die "Version must use dotted numeric notation\n"
    unless $version =~ /\A[0-9]+(?:\.[0-9]+){2}\z/;
$output ||= File::Spec->catfile(
    $FindBin::Bin, '..', "$name-$version.pkg"
);

if (-d $output) {
    $output = File::Spec->catfile($output, "$name-$version.pkg");
}
my $output_parent = dirname($output);
die "Output directory does not exist\n" unless -d $output_parent;
$output = File::Spec->catfile(abs_path($output_parent), basename($output));

my $source = abs_path(File::Spec->catdir($FindBin::Bin, '..', 'conditions'));
die "Conditions payload is missing\n" unless defined $source && -d $source;
my $workspace = tempdir('munki-perls-pkg-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $staging = File::Spec->catdir($workspace, 'payload');
mkpath($staging, 0, 0755);

find(
    {
        no_chdir => 1,
        wanted => sub {
            my $relative = File::Spec->abs2rel($File::Find::name, $source);
            return if $relative eq File::Spec->curdir();
            my $destination = File::Spec->catfile($staging, $relative);
            if (-d $File::Find::name) {
                mkpath($destination, 0, 0755);
                return;
            }
            return unless -f $File::Find::name;
            mkpath(dirname($destination), 0, 0755);
            copy_file($File::Find::name, $destination);
            chmod((stat($File::Find::name))[2] & 07777, $destination)
                or die "Could not set staged file mode\n";
        },
    },
    $source
);

my $built = File::Spec->catfile($workspace, "$name-unsigned.pkg");
if ($verbose) {
    print STDERR "Building $name $version payload\n";
}
local $ENV{COPYFILE_DISABLE} = 1;
run_or_die(
    '/usr/bin/pkgbuild',
    '--root', $staging,
    '--identifier', $identifier,
    '--version', $version,
    '--install-location', $install_location,
    $built,
);

# pkgbuild's own gzip is perfectly adequate. zopfli is not adequate, it is
# obsessive: given the same bytes, it tries far more DEFLATE encodings
# than gzip ever bothers with before picking the smallest, and it still
# writes plain, boring, standards-compliant gzip when it's done. Nothing
# downstream, not the installer, not Leopard, not a G5 that has never
# heard of zopfli, needs to know or care that it was used. Every byte
# counts, and this one is free.
my $zopfli = find_zopfli();
if ($zopfli) {
    squeeze_payload($built, $zopfli, $workspace, $verbose);
} elsif ($verbose) {
    print STDERR "zopfli not found; shipping pkgbuild's own gzip as-is\n";
}

if (defined $sign) {
    print STDERR "Signing with $sign\n" if $verbose;
    run_or_die('/usr/bin/productsign', '--sign', $sign, $built, $output);
} else {
    copy_file($built, $output);
}
print "$output\n";
exit 0;

sub run_or_die {
    my (@command) = @_;
    my $status = system { $command[0] } @command;
    die "$command[0] could not be started\n" if $status == -1;
    die "$command[0] failed\n" if $status != 0;
    return;
}

sub find_zopfli {
    for my $directory (File::Spec->path()) {
        my $candidate = File::Spec->catfile($directory, 'zopfli');
        return $candidate if -f $candidate && -x _;
    }
    return undef;
}

sub pipe_to_file {
    my ($command, $destination) = @_;
    open(my $source_fh, '-|', @{$command})
        or die "Could not start $command->[0]\n";
    binmode $source_fh;
    open(my $destination_fh, '>', $destination)
        or die "Could not create $destination\n";
    binmode $destination_fh;
    while (1) {
        my $count = read($source_fh, my $buffer, 65536);
        die "Could not read from $command->[0]\n" unless defined $count;
        last if $count == 0;
        print {$destination_fh} $buffer
            or die "Could not write $destination\n";
    }
    close $destination_fh or die "Could not close $destination\n";
    close $source_fh or die "$command->[0] failed\n";
    return;
}

sub squeeze_payload {
    my ($pkg_path, $zopfli, $workspace, $verbose) = @_;

    # This whole optimization is a volunteer, not a requirement, so any
    # failure here (a stale zopfli build, a read-only temp filesystem,
    # cosmic rays) just means the package ships exactly as pkgbuild made
    # it. That was already a complete, valid, installable package before
    # this function was ever called.
    my $saved = eval {
        my $expanded = File::Spec->catdir($workspace, 'expanded');
        run_or_die('/usr/sbin/pkgutil', '--expand', $pkg_path, $expanded);

        my $payload = File::Spec->catfile($expanded, 'Payload');
        die "Expanded package has no Payload\n" unless -f $payload;
        my $original_size = (stat($payload))[7];

        my $raw = File::Spec->catfile($workspace, 'payload.cpio');
        pipe_to_file(['/usr/bin/gzip', '-dc', $payload], $raw);

        my $squeezed = File::Spec->catfile($workspace, 'payload.cpio.gz');
        pipe_to_file([$zopfli, '--gzip', '--i15', '-c', $raw], $squeezed);

        # Trust, but verify: confirm the recompressed payload is standard
        # gzip that decompresses back to the exact bytes pkgbuild started
        # with, before it goes anywhere near something that gets shipped.
        my $roundtrip = File::Spec->catfile($workspace, 'payload.roundtrip');
        pipe_to_file(['/usr/bin/gzip', '-dc', $squeezed], $roundtrip);
        die "Recompressed payload does not round-trip\n"
            if compare($raw, $roundtrip) != 0;

        my $squeezed_size = (stat($squeezed))[7];
        die "Recompressed payload was not smaller\n"
            if $squeezed_size >= $original_size;

        copy_file($squeezed, $payload);

        my $reflattened = File::Spec->catfile($workspace, 'reflattened.pkg');
        run_or_die('/usr/sbin/pkgutil', '--flatten', $expanded, $reflattened);
        rename($reflattened, $pkg_path)
            or die "Could not replace package with the squeezed one\n";

        $original_size - $squeezed_size;
    };

    if (!defined $saved) {
        if ($verbose) {
            my $reason = $@ || 'unknown error';
            chomp $reason;
            print STDERR "zopfli optimization skipped: $reason\n";
        }
        return;
    }
    print STDERR "zopfli saved $saved bytes on the payload\n" if $verbose;
    return;
}

sub copy_file {
    my ($source_path, $destination_path) = @_;
    # Copy the bytes, not the source file's personal history.
    open(my $source_fh, '<', $source_path)
        or die "Could not open payload source\n";
    open(my $destination_fh, '>', $destination_path)
        or die "Could not create staged payload file\n";
    binmode $source_fh;
    binmode $destination_fh;
    while (1) {
        my $count = read($source_fh, my $buffer, 65536);
        die "Could not read payload source\n" unless defined $count;
        last if $count == 0;
        print {$destination_fh} $buffer
            or die "Could not write staged payload file\n";
    }
    close $source_fh or die "Could not close payload source\n";
    close $destination_fh or die "Could not close staged payload file\n";
}

sub usage {
    my ($status) = @_;
    print "Usage: $0 [--version VERSION] [--output PATH] [--sign IDENTITY] [--verbose] [--help]\n";
    exit $status;
}
