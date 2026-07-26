use 5.008006;
use strict;
use warnings;

use File::Basename qw(basename);
use File::Path qw(mkpath);
use File::Temp qw(tempdir);
use Scalar::Util qw(blessed);
use Test::More 'no_plan';
use lib 'conditions/lib';
use Foundation;
use MunkiPerls qw(
    foundation_array foundation_dictionary foundation_string load_plist_file
    objc_string write_plist_file
);
use MunkiPerls::Plugins qw(
    collect_plugins discover_plugins load_plugin run_plugins_condition
);

sub write_plugin {
    my ($directory, $name, $source, $mode) = @_;
    my $path = "$directory/$name";
    open(my $handle, '>', $path) or die $!;
    print {$handle} $source;
    close $handle or die $!;
    chmod(defined($mode) ? $mode : 0644, $path) or die $!;
    return $path;
}

my $directory = tempdir(CLEANUP => 1);
chmod 0700, $directory or die $!;

my $first = write_plugin($directory, '00_first.pl', <<'PLUGIN');
use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
sub helper_name { return 'first' }
sub perls {
    my ($context) = @_;
    return {
        collision => perl_string('first'),
        context_path => perl_string($context->{output_path}),
    };
}
1;
PLUGIN

my $types = write_plugin($directory, '10_types.pl', <<'PLUGIN');
use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(
    perl_array perl_bool perl_dictionary perl_integer perl_real perl_string
);
sub perls {
    return {
        enabled => perl_bool(1),
        integer => perl_integer(42),
        mixed => perl_array(
            'plain string',
            perl_integer(7),
            perl_dictionary(nested => perl_bool(0)),
        ),
        multi_key => perl_string('present'),
        nested => perl_dictionary(
            label => 'west',
            ratio => perl_real('1.25'),
        ),
        real => perl_real('3.5'),
    };
}
1;
PLUGIN

write_plugin($directory, '20_invalid.pl', <<'PLUGIN');
use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
sub perls {
    return {
        invalid => { type => 'unsupported', value => 'no' },
        rejected_with_plugin => perl_string('no'),
    };
}
1;
PLUGIN

write_plugin($directory, '30_runtime.pl', <<'PLUGIN');
use 5.008006;
use strict;
use warnings;
sub perls { die "collector exploded\n" }
1;
PLUGIN

write_plugin($directory, '40_missing_interface.pl', <<'PLUGIN');
use 5.008006;
use strict;
use warnings;
1;
PLUGIN

write_plugin($directory, '50_syntax.pl', "use strict; this is not perl;\n");

my $last = write_plugin($directory, '60_last.pl', <<'PLUGIN');
use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
sub helper_name { return 'last' }
sub perls { return { collision => perl_string('last') } }
1;
PLUGIN

write_plugin($directory, '70_empty.pl', <<'PLUGIN');
use 5.008006;
use strict;
use warnings;
sub perls { return {} }
1;
PLUGIN

write_plugin($directory, '.hidden.pl', "sub perls { return {} }\n1;\n");
write_plugin($directory, 'notes.txt', "not a plugin\n");
write_plugin(
    $directory,
    '80_unsafe.pl',
    "sub perls { return {} }\n1;\n",
    0666,
);
mkpath("$directory/90_directory.pl", 0, 0755);
symlink($first, "$directory/95_symlink.pl") or die $!;

my @discovery_diagnostics;
my @discovered = discover_plugins(
    $directory,
    diagnostic => sub { push @discovery_diagnostics, @_ },
);
is_deeply(
    [map { basename($_) } @discovered],
    [qw(
        00_first.pl
        10_types.pl
        20_invalid.pl
        30_runtime.pl
        40_missing_interface.pl
        50_syntax.pl
        60_last.pl
        70_empty.pl
    )],
    'discovery is sorted and includes only safe regular Perl files'
);
like(
    join("\n", @discovery_diagnostics),
    qr{80_unsafe\.pl.*writable by group or others},
    'unsafe permissions are diagnosed'
);
like(
    join("\n", @discovery_diagnostics),
    qr{90_directory\.pl.*not a regular file},
    'plugin-shaped directories are diagnosed'
);
like(
    join("\n", @discovery_diagnostics),
    qr{95_symlink\.pl.*symbolic link},
    'symlinks are diagnosed'
);

my @diagnostics;
my $output_path = "$directory/collected.plist";
my $perls = collect_plugins(
    $directory,
    { output_path => $output_path },
    diagnostic => sub { push @diagnostics, @_ },
    preference_loader => sub { return {} },
    verbose => 1,
);
is($perls->{collision}->{value}, 'last', 'later sorted plugins replace keys');
is(
    $perls->{context_path}->{value},
    $output_path,
    'plugins receive the runner context'
);
is($perls->{integer}->{value}, 42, 'integer descriptors are collected');
is($perls->{real}->{value}, 3.5, 'real descriptors are collected');
ok(exists $perls->{multi_key}, 'one plugin can return multiple keys');
ok(!exists $perls->{invalid}, 'invalid plugin output is rejected');
ok(
    !exists $perls->{rejected_with_plugin},
    'validation failure rejects the entire plugin result'
);
like(
    join("\n", @diagnostics),
    qr{60_last\.pl replaces collision from 00_first\.pl},
    'verbose diagnostics identify deterministic overrides'
);
like(
    join("\n", @diagnostics),
    qr{20_invalid\.pl returned invalid perls},
    'invalid output is diagnosed'
);
like(
    join("\n", @diagnostics),
    qr{30_runtime\.pl failed to collect: collector exploded},
    'runtime failures are isolated and diagnosed'
);
like(
    join("\n", @diagnostics),
    qr{40_missing_interface\.pl failed to load: plugin does not define perls},
    'missing interfaces are diagnosed'
);
like(
    join("\n", @diagnostics),
    qr{50_syntax\.pl failed to load:},
    'syntax failures are isolated and diagnosed'
);

my $first_plugin = load_plugin($first);
my $last_plugin = load_plugin($last);
isnt(
    $first_plugin->{package},
    $last_plugin->{package},
    'each plugin receives an isolated generated package'
);
is(
    $first_plugin->{package}->can('helper_name')->(),
    'first',
    'first plugin helpers remain isolated'
);
is(
    $last_plugin->{package}->can('helper_name')->(),
    'last',
    'later plugin helpers do not replace earlier helpers'
);

my $only_output = "$directory/only.plist";
my @only_arguments = ('--output', $only_output, '--only', '00_first');
my $only_stderr = '';
my $only_status;
{
    local *STDERR;
    open(STDERR, '>', \$only_stderr) or die $!;
    $only_status = run_plugins_condition(
        \@only_arguments,
        plugin_dir => $directory,
        preference_loader => sub { die "must not read preferences\n" },
    );
}
is(
    $only_status,
    0,
    '--only accepts a plugin filename stem'
);
my $only_plist = load_plist_file($only_output, dictionary => 1);
is($only_plist->count(), 2, '--only writes only the selected plugin keys');
is(
    objc_string(
        $only_plist->objectForKey_(foundation_string('collision'))
    ),
    'first',
    '--only runs the selected plugin'
);

my @missing_arguments = (
    '--output', "$directory/missing.plist", '--only', 'not_here'
);
my $missing_stderr = '';
my $missing_status;
{
    local *STDERR;
    open(STDERR, '>', \$missing_stderr) or die $!;
    $missing_status = run_plugins_condition(
        \@missing_arguments,
        plugin_dir => $directory,
    );
}
is($missing_status, 1, 'a missing --only plugin fails');
like($missing_stderr, qr{Plugin not found}, 'missing plugin error is reported');

my $selection_directory = tempdir(CLEANUP => 1);
chmod 0700, $selection_directory or die $!;
my $marker = "$selection_directory/marker";

sub write_marker_plugin {
    my ($name, $keys) = @_;
    my $load_mark = "$name:load";
    my $call_mark = "$name:call";
    my $pairs = join(
        ",\n        ",
        map { "$_ => perl_string('$_')" } @{$keys}
    );
    write_plugin($selection_directory, "$name.pl", <<PLUGIN);
use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
open(my \$loaded, '>>', '$marker') or die \$!;
print {\$loaded} "$load_mark\n";
close \$loaded or die \$!;
sub perls {
    open(my \$called, '>>', '$marker') or die \$!;
    print {\$called} "$call_mark\n";
    close \$called or die \$!;
    return {
        $pairs
    };
}
1;
PLUGIN
}

write_marker_plugin('alpha', ['alpha']);
write_marker_plugin('custom_site', ['custom_one', 'custom_two']);
write_marker_plugin('zulu', ['zulu']);

sub selected_perls {
    my ($preferences, $diagnostics, %options) = @_;
    unlink $marker if -e $marker;
    return collect_plugins(
        $selection_directory,
        {},
        diagnostic => sub { push @{$diagnostics}, @_ },
        preference_loader => sub {
            die "preference bridge failed\n" if $options{fail};
            return $preferences;
        },
        verbose => $options{verbose},
    );
}

sub marker_text {
    return '' unless -e $marker;
    open(my $handle, '<', $marker) or die $!;
    local $/;
    my $text = <$handle>;
    close $handle or die $!;
    return $text;
}

my $config_path = "$selection_directory/config.plist";

sub write_selection_config {
    my ($values) = @_;
    unlink $config_path if -e $config_path || -l $config_path;
    my $root = foundation_dictionary();
    for my $key (keys %{$values}) {
        my $value = $values->{$key};
        if (ref($value) eq 'ARRAY') {
            my $array = foundation_array();
            for my $entry (@{$value}) {
                $array->addObject_(foundation_string($entry));
            }
            $root->setObject_forKey_($array, foundation_string($key));
        } else {
            $root->setObject_forKey_(
                foundation_string($value), foundation_string($key)
            );
        }
    }
    ok(write_plist_file($config_path, $root, 100), 'writes selection config plist');
    chmod 0644, $config_path or die $!;
}

my @selection_diagnostics;
my $selected = selected_perls({}, \@selection_diagnostics, verbose => 1);
is_deeply(
    [sort keys %{$selected}],
    [qw(alpha custom_one custom_two zulu)],
    'missing preference keys select every plugin'
);
like(
    join("\n", @selection_diagnostics),
    qr{plugin selection mode all: 3 matched, 0 skipped},
    'verbose diagnostics report all-mode counts'
);
like(
    join("\n", @selection_diagnostics),
    qr{plugin selection source: no configuration},
    'verbose diagnostics identify the no-configuration source'
);

@selection_diagnostics = ();
write_selection_config({ included_perls => ['alpha', 'alpha.pl', 'unknown'] });
$selected = selected_perls({}, \@selection_diagnostics, verbose => 1);
is_deeply([sort keys %{$selected}], ['alpha'], 'a real local plist selects included plugins');
like(join("\n", @selection_diagnostics), qr{plugin selection source: config\.plist}, 'verbose diagnostics identify config.plist');
unlike(marker_text(), qr{custom_site:(?:load|call)|zulu:(?:load|call)}, 'plist-omitted plugins are never loaded or invoked');

@selection_diagnostics = ();
write_selection_config({ excluded_perls => ['custom_site'] });
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], [qw(alpha zulu)], 'a real local plist excludes plugins');
unlike(marker_text(), qr{custom_site:(?:load|call)}, 'plist-excluded plugins are never loaded or invoked');

@selection_diagnostics = ();
write_selection_config({ included_perls => [], excluded_perls => ['alpha'] });
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply($selected, {}, 'local plist include wins and an empty include selects none');

@selection_diagnostics = ();
write_selection_config({ excluded_perls => [] });
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], [qw(alpha custom_one custom_two zulu)], 'an empty local exclude selects all');

@selection_diagnostics = ();
write_selection_config({ included_perls => 'alpha' });
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply($selected, {}, 'an invalid local include container remains authoritative');
like(join("\n", @selection_diagnostics), qr{included_perls must be an array of strings}, 'an invalid local container is diagnosed');

@selection_diagnostics = ();
write_selection_config({ included_perls => ['alpha', '', '../zulu', 'unknown', 'unknown.pl'] });
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], ['alpha'], 'invalid, duplicate, and unknown local plist entries are skipped');

@selection_diagnostics = ();
write_selection_config({ included_perls => ['alpha'] });
$selected = selected_perls({ included_perls => ['zulu'] }, \@selection_diagnostics, verbose => 1);
is_deeply([sort keys %{$selected}], ['zulu'], 'managed preferences override config.plist');
like(join("\n", @selection_diagnostics), qr{plugin selection source: preferences}, 'verbose diagnostics identify preferences');

write_selection_config({ included_perls => ['zulu'] });
unlink $marker if -e $marker;
$selected = collect_plugins(
    $selection_directory,
    {},
    only => 'alpha',
    preference_loader => sub { die "must not read preferences\n" },
);
is_deeply([sort keys %{$selected}], ['alpha'], '--only bypasses preferences and config.plist');
unlike(marker_text(), qr{zulu:(?:load|call)}, '--only does not load the plist-selected plugin');

@selection_diagnostics = ();
$selected = selected_perls({}, \@selection_diagnostics, fail => 1);
is_deeply([sort keys %{$selected}], ['zulu'], 'preference-read failure falls back to config.plist');
like(join("\n", @selection_diagnostics), qr{preferences could not be read; trying config\.plist: preference bridge failed}, 'preference failure fallback is diagnosed');

@selection_diagnostics = ();
write_selection_config({ unrelated => ['alpha'] });
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], [qw(alpha custom_one custom_two zulu)], 'a keyless plist behaves as no configuration');

unlink $config_path or die $!;
open(my $malformed, '>', $config_path) or die $!;
print {$malformed} 'not a plist';
close $malformed or die $!;
chmod 0644, $config_path or die $!;
@selection_diagnostics = ();
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], [qw(alpha custom_one custom_two zulu)], 'a malformed plist is ignored');
like(join("\n", @selection_diagnostics), qr{config\.plist ignored:.*malformed or is not a dictionary}, 'a malformed plist is diagnosed');

my $non_dictionary = foundation_array();
ok(write_plist_file($config_path, $non_dictionary, 100), 'writes non-dictionary config plist');
chmod 0644, $config_path or die $!;
@selection_diagnostics = ();
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], [qw(alpha custom_one custom_two zulu)], 'a non-dictionary plist is ignored');
like(join("\n", @selection_diagnostics), qr{not a dictionary}, 'a non-dictionary plist is diagnosed');

write_selection_config({ included_perls => ['alpha'] });
chmod 0666, $config_path or die $!;
@selection_diagnostics = ();
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], [qw(alpha custom_one custom_two zulu)], 'a writable config plist is ignored');
like(join("\n", @selection_diagnostics), qr{config\.plist ignored:.*writable by group or others}, 'a writable config plist is diagnosed');

SKIP: {
    skip 'unreadable file behavior is not meaningful as root', 2 if $> == 0;
    chmod 0000, $config_path or die $!;
    @selection_diagnostics = ();
    $selected = selected_perls({}, \@selection_diagnostics);
    is_deeply([sort keys %{$selected}], [qw(alpha custom_one custom_two zulu)], 'an unreadable config plist is ignored');
    like(join("\n", @selection_diagnostics), qr{config\.plist ignored:.*not readable}, 'an unreadable config plist is diagnosed');
}

chmod 0644, $config_path or die $!;
my $config_target = "$selection_directory/config-target.plist";
rename($config_path, $config_target) or die $!;
symlink($config_target, $config_path) or die $!;
@selection_diagnostics = ();
$selected = selected_perls({}, \@selection_diagnostics);
is_deeply([sort keys %{$selected}], [qw(alpha custom_one custom_two zulu)], 'a symlinked config plist is ignored');
like(join("\n", @selection_diagnostics), qr{config\.plist ignored:.*symbolic link}, 'a symlinked config plist is diagnosed');
unlink $config_path or die $!;
unlink $config_target or die $!;

@selection_diagnostics = ();
$selected = selected_perls(
    { included_perls => [] }, \@selection_diagnostics, verbose => 1
);
is_deeply($selected, {}, 'an empty include list selects no plugins');
is(marker_text(), '', 'unselected plugins are neither loaded nor invoked');
like(
    join("\n", @selection_diagnostics),
    qr{plugin selection mode include: 0 matched, 3 skipped},
    'verbose diagnostics report include-mode counts'
);

@selection_diagnostics = ();
$selected = selected_perls(
    { excluded_perls => [] }, \@selection_diagnostics
);
is_deeply(
    [sort keys %{$selected}],
    [qw(alpha custom_one custom_two zulu)],
    'an empty exclude list selects every plugin'
);

@selection_diagnostics = ();
$selected = selected_perls(
    { included_perls => ['alpha', 'custom_site.pl', 'alpha.pl'] },
    \@selection_diagnostics
);
is_deeply(
    [sort keys %{$selected}],
    [qw(alpha custom_one custom_two)],
    'include accepts stems and .pl names, deduplicates, and selects a multi-key plugin as a whole'
);
unlike(marker_text(), qr{zulu:(?:load|call)}, 'an omitted include plugin is not loaded or called');

@selection_diagnostics = ();
$selected = selected_perls(
    { excluded_perls => ['alpha.pl', 'alpha', 'custom_site'] },
    \@selection_diagnostics
);
is_deeply([sort keys %{$selected}], ['zulu'], 'exclude removes valid installed plugins');
unlike(marker_text(), qr{alpha:(?:load|call)|custom_site:(?:load|call)}, 'excluded plugins are not loaded or called');

@selection_diagnostics = ();
$selected = selected_perls(
    {
        included_perls => ['zulu'],
        excluded_perls => { invalid => 1 },
    },
    \@selection_diagnostics
);
is_deeply([sort keys %{$selected}], ['zulu'], 'include takes precedence over exclude');
unlike(
    join("\n", @selection_diagnostics),
    qr{excluded_perls},
    'an excluded list is completely ignored when include is present'
);

@selection_diagnostics = ();
$selected = selected_perls(
    { included_perls => 'alpha' }, \@selection_diagnostics
);
is_deeply($selected, {}, 'an invalid include container cannot fall back to all');
like(
    join("\n", @selection_diagnostics),
    qr{included_perls must be an array of strings},
    'an invalid include container is diagnosed'
);

@selection_diagnostics = ();
$selected = selected_perls(
    {
        included_perls => [
            'alpha', '', '../zulu', "bad\nname", {},
            'unknown_plugin', 'unknown_plugin.pl'
        ],
    },
    \@selection_diagnostics
);
is_deeply([sort keys %{$selected}], ['alpha'], 'invalid, unsafe, and unknown include entries are skipped');
like(join("\n", @selection_diagnostics), qr{entry 1 is invalid}, 'empty entries are diagnosed by index');
like(join("\n", @selection_diagnostics), qr{entry 2 is invalid}, 'unsafe entries are diagnosed by index');
unlike(join("\n", @selection_diagnostics), qr{\.\./|bad\nname}, 'unsafe preference values are not echoed in diagnostics');
like(join("\n", @selection_diagnostics), qr{unknown_plugin\.pl is not an installed plugin}, 'unknown safe plugin names are diagnosed');
is(
    scalar(grep { /unknown_plugin\.pl is not an installed plugin/ }
        @selection_diagnostics),
    1,
    'duplicate unknown plugin names are diagnosed once'
);

@selection_diagnostics = ();
$selected = selected_perls(
    { excluded_perls => 'alpha' }, \@selection_diagnostics
);
is_deeply(
    [sort keys %{$selected}],
    [qw(alpha custom_one custom_two zulu)],
    'an invalid exclude container excludes nothing'
);

@selection_diagnostics = ();
$selected = selected_perls({}, \@selection_diagnostics, fail => 1);
is_deeply(
    [sort keys %{$selected}],
    [qw(alpha custom_one custom_two zulu)],
    'a preference read failure preserves the run-all fallback'
);
like(join("\n", @selection_diagnostics), qr{preferences could not be read; trying config\.plist: preference bridge failed}, 'preference read failures are diagnosed without stopping collection');

my $missing_directory = "$directory/not-a-directory";
my $missing_error = eval { discover_plugins($missing_directory); 1 };
ok(!$missing_error, 'a missing plugin directory is fatal');
like($@, qr{Plugin directory is missing}, 'missing directory is identified');

chmod 0777, $directory or die $!;
my $unsafe_directory = eval { discover_plugins($directory); 1 };
ok(!$unsafe_directory, 'an unsafe plugin directory is fatal');
like($@, qr{Plugin directory is writable}, 'unsafe directory is identified');
chmod 0700, $directory or die $!;
