use 5.008006;
use strict;
use warnings;
use Scalar::Util qw(blessed);
use Foundation;
use MunkiPerls qw(
    perl_string objc_string parse_plist_output system_profiler_snapshot
);
use MunkiPerls::Upgrade qw(cached_hardware_snapshot);

sub _plist_strings_for_key {
    my ($object, $wanted_key) = @_;
    return () unless blessed($object) && $$object;

    if ($object->isKindOfClass_(NSDictionary->class())) {
        my @matches;
        my $keys = $object->keyEnumerator();
        while (my $key_object = $keys->nextObject()) {
            last unless blessed($key_object) && $$key_object;
            my $value = $object->objectForKey_($key_object);
            if (objc_string($key_object) eq $wanted_key) {
                my $text = objc_string($value);
                push @matches, $text if length $text;
            }
            push @matches, _plist_strings_for_key($value, $wanted_key);
        }
        return @matches;
    }

    if ($object->isKindOfClass_(NSArray->class())) {
        my @matches;
        my $items = $object->objectEnumerator();
        while (my $item = $items->nextObject()) {
            last unless blessed($item) && $$item;
            push @matches, _plist_strings_for_key($item, $wanted_key);
        }
        return @matches;
    }
    return ();
}

sub _virtual_machine_type {
    my ($output) = @_;
    my $plist = parse_plist_output($output);
    return 'unknown' unless blessed($plist) && $$plist;

    my @boot_rom_versions = _plist_strings_for_key(
        $plist, 'boot_rom_version'
    );
    for my $version (@boot_rom_versions) {
        return 'vmware' if $version =~ /VMW/i;
    }
    for my $version (@boot_rom_versions) {
        return 'virtualbox' if $version =~ /VirtualBox/i;
    }

    my @ethernet_vendors = _plist_strings_for_key(
        $plist, 'spethernet_vendor-id'
    );
    for my $vendor (@ethernet_vendors) {
        return 'parallels' if $vendor =~ /0x1a(?:b8|f4)/i;
    }
    return 'unknown';
}

sub virtual_type {
    my (%options) = @_;
    my $snapshot = $options{hardware_snapshot};
    return '' unless $snapshot->{is_virtual};

    my ($ok, $output);
    if ($options{profiler_probe}) {
        ($ok, $output) = $options{profiler_probe}->();
    } elsif (defined $options{profiler_output}) {
        ($ok, $output) = (1, $options{profiler_output});
    } else {
        ($ok, $output) = system_profiler_snapshot();
    }
    return $ok ? _virtual_machine_type($output) : 'unknown';
}

sub physical_or_virtual {
    my ($snapshot) = @_;
    return $snapshot->{is_virtual} ? 'virtual' : 'physical';
}

sub perls {
    my ($context) = @_;
    my $snapshot = cached_hardware_snapshot($context->{output_path});
    return {
        virtual_type => perl_string(
            virtual_type(hardware_snapshot => $snapshot)
        ),
        physical_or_virtual => perl_string(
            physical_or_virtual($snapshot)
        ),
    };
}
1;
