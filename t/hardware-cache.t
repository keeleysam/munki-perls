use 5.008006;
use strict;
use warnings;

use File::Temp qw(tempdir);
use POSIX ();
use Scalar::Util qw(blessed);
use Test::More 'no_plan';
use lib 'conditions/lib';
use Foundation;
use MunkiPerls qw(
    foundation_string load_plist_file objc_string write_plist_file
);
use MunkiPerls::Upgrade qw(cached_hardware_snapshot);

sub snapshot {
    my ($marker) = @_;
    return {
        version => '15.5',
        model => "Mac$marker,1",
        hardware_target => "J${marker}AP",
        cpu_type => 'intel',
        cpu_family => '',
        cpu_64bit => $marker % 2,
        cpu_frequency_mhz => 2000 + $marker,
        ram_mb => 8192,
        is_virtual => $marker % 2,
    };
}

sub write_cache_root {
    my ($path, $root) = @_;
    return write_plist_file($path, $root, 100);
}

my $directory = tempdir(CLEANUP => 1);
my $output = "$directory/ConditionalItems.plist";
my $cache = $output . '.munki-perls-hardware-cache.plist';
my $lock = $cache . '.lock';
my $collections = 0;

my $first = cached_hardware_snapshot(
    $output,
    boot_identifier => '{ sec = 100, usec = 0 }',
    collector => sub { $collections++; return snapshot(1) },
);
is_deeply($first, snapshot(1), 'first request returns live hardware');
ok(-f $cache, 'first request creates the hardware cache');
ok(-f $lock, 'hardware cache uses a stable sidecar lock');

my $reused = cached_hardware_snapshot(
    $output,
    boot_identifier => '{ sec = 100, usec = 0 }',
    collector => sub { $collections++; return snapshot(2) },
);
is_deeply($reused, snapshot(1), 'same-boot request reuses cached hardware');
is($collections, 1, 'same-boot reuse skips live collection');

my $cache_root = load_plist_file($cache, dictionary => 1);
ok(blessed($cache_root) && $$cache_root, 'cache is a Foundation dictionary plist');
my @cache_keys;
my $keys = $cache_root->keyEnumerator();
while (my $key = $keys->nextObject()) {
    last unless blessed($key) && $$key;
    push @cache_keys, objc_string($key);
}
is_deeply(
    [sort @cache_keys],
    [sort qw(
        boot_identifier cpu_64bit cpu_family cpu_frequency_mhz cpu_type
        hardware_target is_virtual model ram_mb schema_version version
    )],
    'cache contains only boot, schema, OS, and hardware fields'
);

my $before_inode = (stat($cache))[1];
my $invalidated = cached_hardware_snapshot(
    $output,
    boot_identifier => '{ sec = 200, usec = 0 }',
    collector => sub { $collections++; return snapshot(2) },
);
is_deeply($invalidated, snapshot(2), 'boot change invalidates the cache');
isnt((stat($cache))[1], $before_inode, 'cache invalidation atomically replaces the cache file');

$cache_root = load_plist_file($cache, dictionary => 1);
$cache_root->setObject_forKey_(
    NSNumber->numberWithInt_(999), foundation_string('schema_version')
);
ok(write_cache_root($cache, $cache_root), 'writes schema-mismatch fixture');
my $schema_result = cached_hardware_snapshot(
    $output,
    boot_identifier => '{ sec = 200, usec = 0 }',
    collector => sub { $collections++; return snapshot(3) },
);
is_deeply($schema_result, snapshot(3), 'schema mismatch falls back to live hardware');

open(my $malformed, '>', $cache) or die $!;
print {$malformed} 'not a plist';
close $malformed;
my $malformed_result = cached_hardware_snapshot(
    $output,
    boot_identifier => '{ sec = 200, usec = 0 }',
    collector => sub { $collections++; return snapshot(4) },
);
is_deeply($malformed_result, snapshot(4), 'malformed cache falls back to live hardware');

unlink $cache;
my $missing_boot_count = 0;
for (1 .. 2) {
    my $result = cached_hardware_snapshot(
        $output,
        boot_identifier => '',
        collector => sub { $missing_boot_count++; return snapshot(5) },
    );
    is_deeply($result, snapshot(5), 'missing boot identifier still returns live hardware');
}
is($missing_boot_count, 2, 'missing boot identifier does not reuse a cache');
ok(!-e $cache, 'missing boot identifier does not write a cache');

my $write_failure_count = 0;
my $write_failure = cached_hardware_snapshot(
    $output,
    boot_identifier => 'write-failure-boot',
    collector => sub { $write_failure_count++; return snapshot(6) },
    cache_writer => sub { die "injected write failure\n" },
);
is_deeply($write_failure, snapshot(6), 'cache write failure still returns live hardware');
ok(!-e $cache, 'failed cache write leaves no cache');

my $missing_parent_output = "$directory/missing/ConditionalItems.plist";
my $lock_failure = cached_hardware_snapshot(
    $missing_parent_output,
    boot_identifier => 'lock-failure-boot',
    collector => sub { return snapshot(7) },
);
is_deeply($lock_failure, snapshot(7), 'cache lock failure still returns live hardware');

unlink $cache;
my $collection_log = "$directory/collections.log";
my @children;
for my $number (1 .. 6) {
    my $pid = fork();
    die "fork failed" unless defined $pid;
    if ($pid == 0) {
        my $result = cached_hardware_snapshot(
            $output,
            boot_identifier => 'concurrent-boot',
            collector => sub {
                open(my $log, '>>', $collection_log) or POSIX::_exit(2);
                print {$log} "collected\n";
                close $log;
                select undef, undef, undef, 0.1;
                return snapshot(8);
            },
        );
        # A forked child must not run Perl's normal exit path here: global
        # destruction would fire File::Temp's cleanup END block a second
        # time for the tempdir this process inherited from its parent,
        # deleting it out from under any siblings still using it.
        POSIX::_exit($result->{model} eq snapshot(8)->{model} ? 0 : 3);
    }
    push @children, $pid;
}
for my $pid (@children) {
    waitpid($pid, 0);
    is($?, 0, 'concurrent cache reader completed');
}
open(my $log, '<', $collection_log) or die $!;
my @collections = <$log>;
close $log;
is(scalar @collections, 1, 'cache lock permits one live collection for concurrent readers');
