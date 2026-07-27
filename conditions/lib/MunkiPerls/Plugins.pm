package MunkiPerls::Plugins;

use 5.008006;
use strict;
use warnings;

use Exporter qw(import);
use File::Basename qw(basename);
use File::Spec;
use Getopt::Long qw(GetOptions);
use Scalar::Util qw(blessed);

use MunkiPerls qw(
    foundation_string load_plist_file managed_install_dir objc_string
    validate_perls write_perls
);

our @EXPORT_OK = qw(
    collect_plugins discover_plugins load_plugin run_plugins_condition
);
our $LOAD_SEQUENCE = 0;
our $PREFERENCES_DOMAIN = 'org.munki.perls';

sub _valid_object {
    my ($object) = @_;
    return blessed($object) && $$object;
}

sub _preference_value {
    my ($value) = @_;
    return $value unless _valid_object($value);
    return objc_string($value)
        if $value->isKindOfClass_(NSString->class());
    if ($value->isKindOfClass_(NSArray->class())) {
        my @items;
        for (my $index = 0; $index < $value->count(); $index++) {
            push @items, _preference_value($value->objectAtIndex_($index));
        }
        return \@items;
    }
    return $value;
}

sub _load_preferences {
    my $defaults = NSUserDefaults->standardUserDefaults();
    die "cannot access user defaults\n" unless _valid_object($defaults);
    my $domain = $defaults->persistentDomainForName_(
        foundation_string($PREFERENCES_DOMAIN)
    );
    return {} unless _valid_object($domain);
    die "preferences domain is not a dictionary\n"
        unless $domain->isKindOfClass_(NSDictionary->class());

    my %preferences;
    for my $key (qw(included_perls excluded_perls)) {
        my $value = $domain->objectForKey_(foundation_string($key));
        next unless _valid_object($value);
        $preferences{$key} = _preference_value($value);
    }
    return \%preferences;
}

sub _has_selection_keys {
    my ($configuration) = @_;
    return ref($configuration) eq 'HASH'
        && (exists($configuration->{included_perls})
            || exists($configuration->{excluded_perls}));
}

sub _load_config_plist {
    my ($path) = @_;
    _safe_path($path, 'Configuration file');
    die "Configuration file is not readable: $path\n" unless -r $path;

    my $dictionary = load_plist_file($path, dictionary => 1);
    die "Configuration file is malformed or is not a dictionary: $path\n"
        unless _valid_object($dictionary);

    my %configuration;
    for my $key (qw(included_perls excluded_perls)) {
        my $value = $dictionary->objectForKey_(foundation_string($key));
        next unless _valid_object($value);
        $configuration{$key} = _preference_value($value);
    }
    return \%configuration;
}

sub _owner_uid {
    return $> == 0 ? 0 : $>;
}

sub _safe_path {
    my ($path, $kind) = @_;
    my @metadata = lstat($path);
    die "$kind is missing: $path\n" unless @metadata;
    die "$kind must not be a symbolic link: $path\n" if -l _;
    if ($kind eq 'Plugin directory') {
        die "$kind is not a directory: $path\n" unless -d _;
    } else {
        die "$kind is not a regular file: $path\n" unless -f _;
    }
    die "$kind has an unsafe owner: $path\n"
        unless $metadata[4] == _owner_uid();
    die "$kind is writable by group or others: $path\n"
        if ($metadata[2] & 0022);
    return 1;
}

sub discover_plugins {
    my ($directory, %options) = @_;
    my $diagnostic = $options{diagnostic} || sub { };
    _safe_path($directory, 'Plugin directory');

    opendir(my $handle, $directory)
        or die "Cannot read plugin directory: $directory\n";
    my @names = sort grep {
        $_ !~ /\A\./ && $_ =~ /\.pl\z/
    } readdir($handle);
    closedir $handle or die "Cannot close plugin directory: $directory\n";

    my @paths;
    for my $name (@names) {
        my $path = File::Spec->catfile($directory, $name);
        my $safe = eval { _safe_path($path, 'Plugin') };
        if (!$safe) {
            $diagnostic->(
                "plugin $name skipped: " . _diagnostic_text($@)
            );
            next;
        }
        push @paths, $path;
    }
    return @paths;
}

sub _quoted_path {
    my ($path) = @_;
    $path =~ s/\\/\\\\/g;
    $path =~ s/'/\\'/g;
    return $path;
}

sub load_plugin {
    my ($path) = @_;
    $path = File::Spec->rel2abs($path);
    _safe_path($path, 'Plugin');
    my $package = 'MunkiPerls::LoadedPlugin::P' . ++$LOAD_SEQUENCE;
    my $quoted = _quoted_path($path);
    my $loaded = eval "package $package; do '$quoted'";
    my $error = $@;
    if (!defined $loaded) {
        $error ||= $! || 'plugin returned an undefined value';
        die "$error\n";
    }
    die "plugin returned false while loading\n" unless $loaded;
    my $callback = $package->can('perls');
    die "plugin does not define perls()\n" unless $callback;
    return {
        callback => $callback,
        name => basename($path),
        package => $package,
        path => $path,
    };
}

sub _diagnostic_text {
    my ($error) = @_;
    $error = 'unknown error' unless defined($error) && length($error);
    $error =~ s/[\r\n]+/ /g;
    $error =~ s/\s+\z//;
    return $error;
}

sub _selection_name {
    my ($value) = @_;
    return unless defined($value) && !ref($value) && length($value);
    $value =~ s/\.pl\z//;
    return unless $value =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/;
    return $value . '.pl';
}

sub _select_plugins {
    my ($paths, $preferences, $diagnostic, $verbose) = @_;
    $preferences = {} unless ref($preferences) eq 'HASH';

    my ($mode, $key);
    if (exists $preferences->{included_perls}) {
        ($mode, $key) = ('include', 'included_perls');
    } elsif (exists $preferences->{excluded_perls}) {
        ($mode, $key) = ('exclude', 'excluded_perls');
    } else {
        $mode = 'all';
    }

    my %installed = map { basename($_) => 1 } @{$paths};
    my %seen_names;
    my %selected_names;
    if (defined $key) {
        my $entries = $preferences->{$key};
        if (ref($entries) ne 'ARRAY') {
            $diagnostic->("$key must be an array of strings; no entries used");
        } else {
            for (my $index = 0; $index < @{$entries}; $index++) {
                my $name = _selection_name($entries->[$index]);
                if (!defined $name) {
                    $diagnostic->("$key entry $index is invalid; entry skipped");
                    next;
                }
                next if $seen_names{$name}++;
                if (!$installed{$name}) {
                    $diagnostic->("$key entry $name is not an installed plugin; entry skipped");
                    next;
                }
                $selected_names{$name} = 1;
            }
        }
    }

    my @selected;
    if ($mode eq 'all') {
        @selected = @{$paths};
    } elsif ($mode eq 'include') {
        @selected = grep { $selected_names{basename($_)} } @{$paths};
    } else {
        @selected = grep { !$selected_names{basename($_)} } @{$paths};
    }
    if ($verbose) {
        $diagnostic->(
            "plugin selection mode $mode: " . scalar(@selected)
                . " matched, " . (scalar(@{$paths}) - scalar(@selected))
                . " skipped"
        );
    }
    return @selected;
}

sub collect_plugins {
    my ($directory, $context, %options) = @_;
    $context ||= {};
    my $diagnostic = $options{diagnostic} || sub { };
    my $only = $options{only};
    if (defined $only) {
        die "Plugin name must not contain a path separator\n"
            if $only =~ m{[/\\]};
        $only .= '.pl' unless $only =~ /\.pl\z/;
    }

    my @paths = discover_plugins(
        $directory,
        diagnostic => $diagnostic,
    );
    if (defined $only) {
        @paths = grep { basename($_) eq $only } @paths;
        die "Plugin not found: $only\n" unless @paths;
    } else {
        my $loader = $options{preference_loader} || \&_load_preferences;
        my $preferences = eval { $loader->() };
        my $preference_error = $@;
        my $configuration;
        my $source;
        if (!$preference_error && _has_selection_keys($preferences)) {
            $configuration = $preferences;
            $source = 'preferences';
        } else {
            if ($preference_error) {
                $diagnostic->(
                    'preferences could not be read; trying config.plist: '
                        . _diagnostic_text($preference_error)
                );
            }
            my $config_path = $options{config_path};
            $config_path = File::Spec->catfile($directory, 'config.plist')
                unless defined $config_path;
            if (-e $config_path || -l $config_path) {
                my $local = eval { _load_config_plist($config_path) };
                my $config_error = $@;
                if ($config_error) {
                    $diagnostic->(
                        'config.plist ignored: '
                            . _diagnostic_text($config_error)
                    );
                } elsif (_has_selection_keys($local)) {
                    $configuration = $local;
                    $source = 'config.plist';
                }
            }
        }
        if (!$configuration) {
            $configuration = {};
            $source = 'no configuration';
        }
        if ($options{verbose}) {
            $diagnostic->(
                "plugin selection source: $source"
            );
        }
        @paths = _select_plugins(
            \@paths, $configuration, $diagnostic, $options{verbose}
        );
    }

    my %merged;
    my %owners;
    for my $path (@paths) {
        my $name = basename($path);
        my $plugin = eval { load_plugin($path) };
        if (!$plugin) {
            $diagnostic->(
                "plugin $name failed to load: " . _diagnostic_text($@)
            );
            next;
        }

        my $perls = eval { $plugin->{callback}->($context) };
        if (!$perls || $@) {
            $diagnostic->(
                "plugin $name failed to collect: " . _diagnostic_text($@)
            );
            next;
        }
        my $valid = eval { validate_perls($perls) };
        if (!$valid) {
            $diagnostic->(
                "plugin $name returned invalid perls: "
                    . _diagnostic_text($@)
            );
            next;
        }

        for my $key (sort keys %{$perls}) {
            if (exists $merged{$key} && $options{verbose}) {
                $diagnostic->(
                    "plugin $name replaces $key from $owners{$key}"
                );
            }
            $merged{$key} = $perls->{$key};
            $owners{$key} = $name;
        }
    }
    return \%merged;
}

sub _usage {
    my ($program) = @_;
    return "Usage: $program [--output PATH] [--only NAME] [--verbose] [--help]\n";
}

sub run_plugins_condition {
    my ($argv, %options) = @_;
    my $output;
    my $only;
    my $verbose = 0;
    my $help = 0;
    my @args = @{$argv};
    my $ok;
    {
        local @ARGV = @args;
        $ok = GetOptions(
            'output=s' => \$output,
            'only=s' => \$only,
            'verbose' => \$verbose,
            'help' => \$help,
        );
        @args = @ARGV;
    }
    if (!$ok || @args) {
        print STDERR _usage($0);
        return 2;
    }
    if ($help) {
        print _usage($0);
        return 0;
    }

    $output ||= File::Spec->catfile(
        managed_install_dir(), 'ConditionalItems.plist'
    );
    my $debug = $verbose || ($ENV{MUNKI_PERLS_DEBUG} || '') eq '1';
    my $diagnostic = sub {
        print STDERR "munki-perls: $_[0]\n";
    };
    $diagnostic->('collecting plugins') if $debug;

    my $perls = eval {
        collect_plugins(
            $options{plugin_dir},
            { output_path => $output },
            diagnostic => $diagnostic,
            only => $only,
            config_path => $options{config_path},
            preference_loader => $options{preference_loader},
            verbose => $debug,
        );
    };
    if (!$perls || $@) {
        $diagnostic->('plugin collection failed: ' . _diagnostic_text($@));
        return 1;
    }
    my $saved = eval { write_perls($output, $perls) };
    if (!$saved || $@) {
        $diagnostic->('plist update failed: ' . _diagnostic_text($@));
        return 1;
    }
    $diagnostic->('perls saved') if $debug;
    return 0;
}

1;
