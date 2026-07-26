#!/usr/bin/perl
use 5.008006;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(basename dirname);
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

my @command = (
    '/usr/bin/pkgbuild',
    '--root', $staging,
    '--identifier', $identifier,
    '--version', $version,
    '--install-location', $install_location,
);
push @command, '--sign', $sign if defined $sign;
push @command, $output;
if ($verbose) {
    my $description = defined $sign ? "signed with $sign" : 'unsigned';
    print STDERR "Building $description $name $version package\n";
}
local $ENV{COPYFILE_DISABLE} = 1;
my $status = system { $command[0] } @command;
die "pkgbuild could not be started\n" if $status == -1;
die "pkgbuild failed\n" if $status != 0;
print "$output\n";
exit 0;

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
