use 5.008006;
use strict;
use warnings;

use File::Path qw(mkpath);
use File::Temp qw(tempdir tempfile);
use POSIX ();
use Scalar::Util qw(blessed);
use Test::More 'no_plan';
use lib 'conditions/lib';
use Foundation;
use MunkiPerls qw(
    perl_array perl_bool perl_dictionary perl_integer perl_real perl_string
    foundation_array foundation_dictionary foundation_string load_plist_file
    objc_string run_condition write_perls write_plist_file
);

sub save_native {
    my ($path, $root, $format) = @_;
    return write_plist_file($path, $root, $format);
}

sub value_for {
    my ($plist, $key) = @_;
    return $plist->objectForKey_(foundation_string($key));
}

sub capture_condition {
    my ($argv, $callback) = @_;
    my ($stdout, $stderr) = ('', '');
    my $status;
    {
        local *STDOUT;
        local *STDERR;
        open(STDOUT, '>', \$stdout) or die $!;
        open(STDERR, '>', \$stderr) or die $!;
        $status = run_condition($argv, $callback);
    }
    return ($status, $stdout, $stderr);
}

my $directory = tempdir(CLEANUP => 1);
my $context_output = "$directory/context.plist";
my $callback_output;
my @context_arguments = ('--output', $context_output);
is(run_condition(
    \@context_arguments,
    sub {
        my ($context) = @_;
        $callback_output = $context->{output_path};
        return { context => perl_string('received') };
    },
), 0, 'condition runner accepts a callback context');
is($callback_output, $context_output, 'callback context contains the resolved output path');
is_deeply(
    \@context_arguments,
    ['--output', $context_output],
    'successful parsing leaves its input array unchanged'
);

my @global_arguments = ('global', 'arguments');
my @help_arguments = ('--help');
my ($cli_status, $cli_stdout, $cli_stderr);
{
    local @ARGV = @global_arguments;
    ($cli_status, $cli_stdout, $cli_stderr) = capture_condition(
        \@help_arguments,
        sub { die "help must not collect perls\n" },
    );
    is_deeply(\@ARGV, \@global_arguments, 'condition runner preserves localized global arguments');
}
is_deeply(\@help_arguments, ['--help'], 'condition runner leaves its input array unchanged');
is($cli_status, 0, 'help exits successfully');
like($cli_stdout, qr{\AUsage: }, 'help prints usage to standard output');
is($cli_stderr, '', 'help does not print an error');

my @unknown_arguments = ('--unknown');
($cli_status, $cli_stdout, $cli_stderr) = capture_condition(
    \@unknown_arguments,
    sub { die "unknown options must not collect perls\n" },
);
is($cli_status, 2, 'unknown option is rejected');
is_deeply(\@unknown_arguments, ['--unknown'], 'unknown-option input remains unchanged');
like($cli_stderr, qr{Usage: }, 'unknown option prints usage to standard error');

my @positional_arguments = ('unexpected');
($cli_status, $cli_stdout, $cli_stderr) = capture_condition(
    \@positional_arguments,
    sub { die "positional arguments must not collect perls\n" },
);
is($cli_status, 2, 'positional argument is rejected');
is_deeply(\@positional_arguments, ['unexpected'], 'positional input remains unchanged');
like($cli_stderr, qr{Usage: }, 'positional argument prints usage to standard error');

my $absent = "$directory/absent.plist";
ok(write_perls($absent, { greeting => perl_string('hello') }), 'creates absent plist');
is(objc_string(value_for(load_plist_file($absent, dictionary => 1), 'greeting')),
    'hello', 'reads newly created XML plist');

my $binary = "$directory/binary.plist";
my $binary_root = foundation_dictionary();
$binary_root->setObject_forKey_(foundation_string('preserved'), foundation_string('old'));
ok(save_native($binary, $binary_root, 200), 'creates binary plist with Foundation');
ok(write_perls($binary, { new => perl_bool(1) }), 'merges binary input');
my $binary_result = load_plist_file($binary, dictionary => 1);
is(objc_string(value_for($binary_result, 'old')), 'preserved', 'preserves binary plist value');
is(value_for($binary_result, 'new')->objCType(), 'c', 'writes native boolean');

my $rich = "$directory/rich.plist";
my $rich_root = foundation_dictionary();
my $nested = foundation_dictionary();
$nested->setObject_forKey_(foundation_string('inside'), foundation_string('nested'));
$rich_root->setObject_forKey_($nested, foundation_string('dictionary'));
my $date = NSDate->dateWithTimeIntervalSince1970_(123456789);
$rich_root->setObject_forKey_($date, foundation_string('date'));
my ($raw_fh, $raw_path) = tempfile(DIR => $directory);
binmode $raw_fh;
print {$raw_fh} "\x01\x02\x03";
close $raw_fh;
my $raw_data = NSData->dataWithContentsOfFile_(foundation_string($raw_path));
$rich_root->setObject_forKey_($raw_data, foundation_string('data'));
ok(save_native($rich, $rich_root, 100), 'creates rich XML plist');
ok(write_perls($rich, {
    unicode => perl_string("J\x{00fc}rgen \x{1f680}"),
    enabled => perl_bool(0),
    integer => perl_integer(42),
    real => perl_real('3.25'),
    names => perl_array('one', "\x{4e8c}"),
    mixed => perl_array(
        'plain',
        perl_integer(7),
        perl_dictionary(nested => perl_bool(1)),
    ),
    recursive => perl_dictionary(
        label => 'west',
        values => perl_array(perl_real('1.5'), perl_bool(0)),
    ),
}), 'merges Unicode and typed perls');
my $rich_result = load_plist_file($rich, dictionary => 1);
is(objc_string(value_for($rich_result, 'unicode')), "J\x{00fc}rgen \x{1f680}", 'Unicode round trips');
is(value_for($rich_result, 'enabled')->objCType(), 'c', 'false remains a boolean');
is(value_for($rich_result, 'integer')->longLongValue(), 42, 'integer remains numeric');
cmp_ok(
    abs(value_for($rich_result, 'real')->doubleValue() - 3.25),
    '<', 0.0001, 'real remains numeric'
);
ok(value_for($rich_result, 'names')->isKindOfClass_(NSArray->class()), 'array has native type');
my $mixed = value_for($rich_result, 'mixed');
ok($mixed->isKindOfClass_(NSArray->class()), 'mixed array has native type');
is(objc_string($mixed->objectAtIndex_(0)), 'plain', 'bare array scalar becomes a string');
is($mixed->objectAtIndex_(1)->longLongValue(), 7, 'mixed array preserves an integer');
ok(
    $mixed->objectAtIndex_(2)->isKindOfClass_(NSDictionary->class()),
    'mixed array preserves a dictionary'
);
my $recursive = value_for($rich_result, 'recursive');
ok(
    $recursive->isKindOfClass_(NSDictionary->class()),
    'recursive dictionary has native type'
);
is(
    objc_string(value_for($recursive, 'label')),
    'west',
    'bare dictionary scalar becomes a string'
);
ok(
    value_for($recursive, 'values')->isKindOfClass_(NSArray->class()),
    'dictionary preserves a nested array'
);
ok(value_for($rich_result, 'dictionary')->isKindOfClass_(NSDictionary->class()), 'nested dictionary preserved');
cmp_ok(abs(value_for($rich_result, 'date')->timeIntervalSince1970() - 123456789), '<', 1, 'date preserved');
is(value_for($rich_result, 'data')->length(), 3, 'data preserved');

for my $case (
    [ malformed => 'this is not a plist' ],
    [ empty => '' ],
) {
    my $path = "$directory/$case->[0].plist";
    open(my $fh, '>', $path) or die $!;
    print {$fh} $case->[1];
    close $fh;
    ok(write_perls($path, { recovered => perl_string('yes') }), "$case->[0] plist is recovered");
    is(objc_string(value_for(load_plist_file($path, dictionary => 1), 'recovered')),
        'yes', "$case->[0] recovery is valid");
}

my $non_dictionary = "$directory/array-root.plist";
my $array_root = foundation_array();
$array_root->addObject_(foundation_string('unrelated'));
ok(save_native($non_dictionary, $array_root, 100), 'creates non-dictionary plist');
ok(write_perls($non_dictionary, { recovered => perl_string('yes') }), 'non-dictionary root is replaced');
ok(load_plist_file($non_dictionary, dictionary => 1), 'replacement root is a dictionary');

my $concurrent = "$directory/concurrent.plist";
my @children;
for my $number (1 .. 8) {
    my $pid = fork();
    die "fork failed" unless defined $pid;
    if ($pid == 0) {
        my $ok = eval {
            write_perls($concurrent, { "key$number" => perl_string("value$number") });
        };
        # A forked child must not run Perl's normal exit path here: global
        # destruction would fire File::Temp's cleanup END block a second
        # time for the tempdir this process inherited from its parent,
        # deleting it out from under any siblings still using it.
        POSIX::_exit($ok ? 0 : 1);
    }
    push @children, $pid;
}
for my $pid (@children) {
    waitpid($pid, 0);
    is($?, 0, 'concurrent writer completed');
}
my $concurrent_result = load_plist_file($concurrent, dictionary => 1);
is($concurrent_result->count(), 8, 'sidecar locking preserves every concurrent update');

my $atomic = "$directory/atomic.plist";
write_perls($atomic, { first => perl_string('one') });
my $before_inode = (stat($atomic))[1];
write_perls($atomic, { second => perl_string('two') });
my $after_inode = (stat($atomic))[1];
isnt($after_inode, $before_inode, 'atomic Foundation write replaces the destination');

SKIP: {
    skip 'permission behavior is not meaningful as root', 1 if $> == 0;
    my $locked_directory = "$directory/no-write";
    mkpath($locked_directory, 0, 0500);
    my $failure = eval {
        write_perls("$locked_directory/output.plist", { key => perl_string('value') });
        1;
    };
    ok(!$failure, 'permission failure is reported');
    chmod 0700, $locked_directory;
}
