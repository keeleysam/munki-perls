package MunkiPerls;

use 5.008006;
use strict;
use warnings;

use Exporter qw(import);
use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempfile);
use Getopt::Long qw(GetOptions);
use POSIX ();
use Scalar::Util qw(blessed);

use Foundation;

our @EXPORT_OK = qw(
    perl_array perl_bool perl_dictionary perl_integer perl_real perl_string
    foundation_array foundation_dictionary foundation_string
    load_plist_file managed_install_dir objc_string parse_plist_output
    run_command run_condition serialize_plist system_version
    validate_perls write_perls write_plist_file
);

use constant NS_PROPERTY_LIST_MUTABLE_CONTAINERS => 1;
use constant NS_PROPERTY_LIST_XML_FORMAT_V1_0    => 100;
use constant NS_UTF8_STRING_ENCODING             => 4;

sub _valid_object {
    my ($object) = @_;
    return blessed($object) && $$object;
}

sub foundation_string {
    my ($value) = @_;
    $value = '' unless defined $value;
    if (utf8::is_utf8($value)) {
        require Encode;
        $value = Encode::encode('UTF-8', $value);
    }
    return NSString->stringWithUTF8String_($value);
}

sub objc_string {
    my ($object) = @_;
    return '' unless _valid_object($object);

    my $string;
    if ($object->isKindOfClass_(NSString->class())) {
        $string = $object;
    } elsif ($object->isKindOfClass_(NSData->class())) {
        $string = NSString->alloc()->initWithData_encoding_(
            $object, NS_UTF8_STRING_ENCODING
        );
        return '' unless _valid_object($string);
    } else {
        return '';
    }

    my $bytes = $string->UTF8String();
    return '' unless defined $bytes;
    $bytes =~ s/\0+\z//;
    return $bytes if utf8::is_utf8($bytes);
    require Encode;
    return Encode::decode('UTF-8', $bytes, Encode::FB_DEFAULT());
}

sub foundation_dictionary {
    return NSMutableDictionary->dictionary();
}

sub foundation_array {
    return NSMutableArray->array();
}

sub perl_string {
    my ($value) = @_;
    return { type => 'string', value => defined($value) ? $value : '' };
}

sub perl_bool {
    my ($value) = @_;
    return { type => 'bool', value => $value ? 1 : 0 };
}

sub perl_integer {
    my ($value) = @_;
    die "Integer perl value is required\n"
        unless defined($value) && $value =~ /\A[+-]?[0-9]+\z/;
    return { type => 'integer', value => 0 + $value };
}

sub perl_real {
    my ($value) = @_;
    die "Real perl value is required\n" unless defined $value;
    die "Invalid real perl value\n"
        unless $value =~ /\A[+-]?(?:(?:[0-9]+(?:\.[0-9]*)?)|(?:\.[0-9]+))(?:[eE][+-]?[0-9]+)?\z/;
    return { type => 'real', value => 0 + $value };
}

sub _descriptor {
    my ($value) = @_;
    return $value
        if ref($value) eq 'HASH' && defined($value->{type});
    return perl_string($value);
}

sub perl_array {
    my (@values) = @_;
    my @descriptors = map { _descriptor($_) } @values;
    return { type => 'array', value => \@descriptors };
}

sub perl_dictionary {
    my @arguments = @_;
    my $values;
    if (@arguments == 1 && ref($arguments[0]) eq 'HASH') {
        $values = $arguments[0];
    } else {
        die "Dictionary perl requires key/value pairs\n"
            if @arguments % 2;
        $values = { @arguments };
    }

    my %descriptors;
    for my $key (keys %{$values}) {
        die "Dictionary perl keys must be defined strings\n"
            if !defined($key) || ref($key);
        $descriptors{$key} = _descriptor($values->{$key});
    }
    return { type => 'dictionary', value => \%descriptors };
}

sub _validate_descriptor {
    my ($perl, $location) = @_;
    $location ||= 'perl';
    die "Invalid descriptor at $location\n"
        unless ref($perl) eq 'HASH' && defined($perl->{type});

    my $type = $perl->{type};
    if ($type eq 'string') {
        die "Invalid string descriptor at $location\n"
            if ref($perl->{value});
        return 1;
    }
    if ($type eq 'bool') {
        die "Invalid boolean descriptor at $location\n"
            if ref($perl->{value});
        return 1;
    }
    if ($type eq 'integer') {
        die "Invalid integer descriptor at $location\n"
            unless defined($perl->{value})
                && !ref($perl->{value})
                && $perl->{value} =~ /\A[+-]?[0-9]+\z/;
        return 1;
    }
    if ($type eq 'real') {
        die "Invalid real descriptor at $location\n"
            unless defined($perl->{value})
                && !ref($perl->{value})
                && $perl->{value} =~ /\A[+-]?(?:(?:[0-9]+(?:\.[0-9]*)?)|(?:\.[0-9]+))(?:[eE][+-]?[0-9]+)?\z/;
        return 1;
    }
    if ($type eq 'array') {
        die "Invalid array descriptor at $location\n"
            unless ref($perl->{value}) eq 'ARRAY';
        for (my $index = 0; $index < @{$perl->{value}}; $index++) {
            _validate_descriptor(
                $perl->{value}->[$index], "$location\[$index\]"
            );
        }
        return 1;
    }
    if ($type eq 'dictionary') {
        die "Invalid dictionary descriptor at $location\n"
            unless ref($perl->{value}) eq 'HASH';
        for my $key (sort keys %{$perl->{value}}) {
            die "Invalid dictionary key at $location\n"
                if !defined($key) || ref($key);
            _validate_descriptor(
                $perl->{value}->{$key}, "$location.$key"
            );
        }
        return 1;
    }
    die "Unsupported perl type at $location: $type\n";
}

sub validate_perls {
    my ($perls) = @_;
    die "Perls must be a hash reference\n" unless ref($perls) eq 'HASH';
    for my $key (sort keys %{$perls}) {
        die "Perl keys must be non-empty strings\n"
            if !defined($key) || ref($key) || !length($key);
        _validate_descriptor($perls->{$key}, $key);
    }
    return 1;
}

sub _perl_object {
    my ($perl) = @_;
    _validate_descriptor($perl);

    if ($perl->{type} eq 'string') {
        return foundation_string($perl->{value});
    }
    if ($perl->{type} eq 'bool') {
        return NSNumber->numberWithBool_($perl->{value} ? 1 : 0);
    }
    if ($perl->{type} eq 'integer') {
        return NSNumber->numberWithLongLong_($perl->{value});
    }
    if ($perl->{type} eq 'real') {
        return NSNumber->numberWithDouble_($perl->{value});
    }
    if ($perl->{type} eq 'array') {
        my $array = foundation_array();
        my $values = $perl->{value};
        for my $value (@{$values}) {
            $array->addObject_(_perl_object($value));
        }
        return $array;
    }
    if ($perl->{type} eq 'dictionary') {
        my $dictionary = foundation_dictionary();
        for my $key (sort keys %{$perl->{value}}) {
            $dictionary->setObject_forKey_(
                _perl_object($perl->{value}->{$key}),
                foundation_string($key)
            );
        }
        return $dictionary;
    }
    die "Unsupported perl type: $perl->{type}\n";
}

sub load_plist_file {
    my ($path, %options) = @_;
    return unless defined $path && -e $path;

    my $data = NSData->dataWithContentsOfFile_(foundation_string($path));
    return unless _valid_object($data);

    my $plist = eval {
        NSPropertyListSerialization->propertyListFromData_mutabilityOption_format_errorDescription_(
            $data, NS_PROPERTY_LIST_MUTABLE_CONTAINERS, undef, undef
        );
    };
    return unless _valid_object($plist);

    if ($options{dictionary}) {
        return unless $plist->isKindOfClass_(NSDictionary->class());
    }
    return $plist;
}

sub parse_plist_output {
    my ($bytes) = @_;
    return unless defined $bytes && length $bytes;

    my ($fh, $path) = tempfile('munki-perls-plist-XXXXXX', TMPDIR => 1);
    binmode $fh;
    print {$fh} $bytes or do {
        close $fh;
        unlink $path;
        return;
    };
    close $fh or do {
        unlink $path;
        return;
    };
    my $plist = load_plist_file($path);
    unlink $path;
    return $plist;
}

sub managed_install_dir {
    my $fallback = '/Library/Managed Installs';
    my $defaults = eval { NSUserDefaults->standardUserDefaults() };
    return $fallback unless _valid_object($defaults);

    my $domain = eval {
        $defaults->persistentDomainForName_(
            foundation_string('ManagedInstalls')
        );
    };
    return $fallback unless _valid_object($domain);

    my $value = eval {
        $domain->objectForKey_(foundation_string('ManagedInstallDir'));
    };
    my $path = objc_string($value);
    return length($path) ? $path : $fallback;
}

sub system_version {
    my ($path) = @_;
    $path ||= '/System/Library/CoreServices/SystemVersion.plist';
    my $plist = load_plist_file($path, dictionary => 1);
    return '' unless _valid_object($plist);
    return objc_string(
        $plist->objectForKey_(foundation_string('ProductVersion'))
    );
}

sub _new_dictionary {
    return foundation_dictionary();
}

sub serialize_plist {
    my ($object, $format) = @_;
    return unless _valid_object($object);
    $format = NS_PROPERTY_LIST_XML_FORMAT_V1_0 unless defined $format;

    my $data = eval {
        NSPropertyListSerialization->dataFromPropertyList_format_errorDescription_(
            $object, $format, undef
        );
    };
    return unless _valid_object($data);
    return $data;
}

sub write_plist_file {
    my ($path, $object, $format) = @_;
    return unless defined($path) && length($path);
    my $data = serialize_plist($object, $format);
    return unless _valid_object($data);
    return $data->writeToFile_atomically_(
        foundation_string($path), 1
    ) ? 1 : 0;
}

sub write_perls {
    my ($path, $perls) = @_;
    die "Output path is required\n" unless defined $path && length $path;
    validate_perls($perls);

    # One property list, one pen.
    my $lock_path = $path . '.lock';
    sysopen(my $lock, $lock_path, O_RDWR | O_CREAT, 0600)
        or die "Cannot open plist lock: $!\n";
    flock($lock, LOCK_EX) or die "Cannot lock plist: $!\n";

    my $plist;
    if (-e $path) {
        die "Cannot read existing plist\n" unless -r $path;
        $plist = load_plist_file($path, dictionary => 1);
    }
    $plist ||= _new_dictionary();

    for my $key (sort keys %{$perls}) {
        $plist->setObject_forKey_(
            _perl_object($perls->{$key}),
            foundation_string($key)
        );
    }

    # Munki prefers its booleans to remain actual booleans.
    my $valid = NSPropertyListSerialization->propertyList_isValidForFormat_(
        $plist, NS_PROPERTY_LIST_XML_FORMAT_V1_0
    );
    die "Conditional items are not a valid property list\n" unless $valid;

    die "Could not atomically write conditional items\n"
        unless write_plist_file(
            $path, $plist, NS_PROPERTY_LIST_XML_FORMAT_V1_0
        );
    close $lock or die "Cannot close plist lock: $!\n";
    return 1;
}

sub run_command {
    my ($options, @command) = @_;
    if (ref($options) ne 'HASH') {
        unshift @command, $options;
        $options = {};
    }
    die "Command is required\n" unless @command;
    die "Command must be absolute\n" unless $command[0] =~ m{\A/};

    # The shell is not invited; it tends to bring interpretation with it.
    pipe(my $read_output, my $write_output) or die "pipe: $!\n";
    pipe(my $read_input, my $write_input) or die "pipe: $!\n";
    my $pid = fork();
    die "fork: $!\n" unless defined $pid;

    if ($pid == 0) {
        close $read_output;
        close $write_input;
        open STDIN, '<&', $read_input or POSIX::_exit(126);
        open STDOUT, '>&', $write_output or POSIX::_exit(126);
        if (!$options->{keep_stderr}) {
            open STDERR, '>', '/dev/null' or POSIX::_exit(126);
        }
        close $read_input;
        close $write_output;
        exec {$command[0]} @command or POSIX::_exit(127);
    }

    close $write_output;
    close $read_input;
    my $input = defined($options->{stdin}) ? $options->{stdin} : '';
    if (length $input) {
        print {$write_input} $input;
    }
    close $write_input;
    local $/;
    my $output = <$read_output>;
    close $read_output;
    waitpid($pid, 0);
    my $status = $?;
    return ($status == 0 ? 1 : 0, defined($output) ? $output : '', $status);
}

sub _usage {
    my ($program) = @_;
    return "Usage: $program [--output PATH] [--verbose] [--help]\n";
}

sub run_condition {
    my ($argv, $callback) = @_;
    my $output;
    my $verbose = 0;
    my $help = 0;
    my @args = @{$argv};
    my $ok;
    {
        local @ARGV = @args;
        $ok = GetOptions(
            'output=s' => \$output,
            'verbose'  => \$verbose,
            'help'     => \$help,
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

    $output ||= File::Spec->catfile(managed_install_dir(), 'ConditionalItems.plist');
    my $debug = $verbose || ($ENV{MUNKI_PERLS_DEBUG} || '') eq '1';
    print STDERR "munki-perls: collecting perls\n" if $debug;
    my $perls = eval { $callback->({ output_path => $output }) };
    if (!$perls || $@) {
        print STDERR "munki-perls: perl collection failed\n";
        return 1;
    }
    my $saved = eval { write_perls($output, $perls) };
    if (!$saved || $@) {
        print STDERR "munki-perls: plist update failed\n";
        return 1;
    }
    print STDERR "munki-perls: perls saved\n" if $debug;
    return 0;
}

1;
