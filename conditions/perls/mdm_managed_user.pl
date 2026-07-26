use 5.008006;
use strict;
use warnings;
use Scalar::Util qw(blessed);
use Foundation;
use MunkiPerls qw(
    perl_string objc_string parse_plist_output run_command
);

sub _managed_uuid_in_object {
    my ($object) = @_;
    return unless blessed($object) && $$object;

    if ($object->isKindOfClass_(NSDictionary->class())) {
        my $keys = $object->keyEnumerator();
        while (my $key_object = $keys->nextObject()) {
            last unless blessed($key_object) && $$key_object;
            my $key = objc_string($key_object);
            my $value = $object->objectForKey_($key_object);
            if ($key =~ /managed[ _-]*user/i) {
                my $text = objc_string($value);
                return $1 if $text =~ /([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})/;
            }
            my $found = _managed_uuid_in_object($value);
            return $found if defined $found;
        }
        return;
    }

    if ($object->isKindOfClass_(NSArray->class())) {
        my $items = $object->objectEnumerator();
        while (my $item = $items->nextObject()) {
            last unless blessed($item) && $$item;
            my $found = _managed_uuid_in_object($item);
            return $found if defined $found;
        }
        return;
    }

    if ($object->isKindOfClass_(NSString->class())) {
        my $text = objc_string($object);
        return $1 if $text =~ /Managed\s+User\s*:\s*([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})/i;
    }
    return;
}

sub mdm_managed_user {
    my (%options) = @_;
    my ($ok, $output);
    if (defined $options{profile_output}) {
        ($ok, $output) = (1, $options{profile_output});
    } else {
        ($ok, $output) = run_command(
            {}, '/usr/sbin/system_profiler', '-xml',
            'SPConfigurationProfileDataType'
        );
    }
    return 'NONE' unless $ok;
    my $plist = parse_plist_output($output);
    my $uuid = _managed_uuid_in_object($plist);
    return 'NONE' unless defined $uuid;

    my ($search_ok, $search_output);
    if ($options{directory_search}) {
        ($search_ok, $search_output) = $options{directory_search}->($uuid);
    } else {
        ($search_ok, $search_output) = run_command(
            {}, '/usr/bin/dscl', '.', '-search', '/Users',
            'GeneratedUID', $uuid
        );
    }
    if ($search_ok && $search_output =~ /\A\s*([^\s]+)/) {
        return $1;
    }
    return $uuid;
}

sub perls {
    return { mdm_managed_user => perl_string(mdm_managed_user()) };
}
1;
