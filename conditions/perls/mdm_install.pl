use 5.008006;
use strict;
use warnings;
use POSIX qw(strftime);
use Scalar::Util qw(blessed);
use Foundation;
use MunkiPerls qw(
    objc_string parse_plist_output perl_integer perl_string run_command
);

sub _valid_object {
    my ($object) = @_;
    return blessed($object) && $$object;
}

sub _date_epoch {
    my ($object) = @_;
    return unless _valid_object($object);

    if ($object->isKindOfClass_(NSDate->class())) {
        return int($object->timeIntervalSince1970());
    }

    my $text = objc_string($object);
    return unless length $text;
    if ($text =~ /\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:Z| ?([+-])(\d{2})(\d{2}))?\z/) {
        require Time::Local;
        my $epoch = Time::Local::timegm($6, $5, $4, $3, $2 - 1, $1);
        if (defined $7) {
            my $offset = ($8 * 3600) + ($9 * 60);
            $epoch += $7 eq '-' ? $offset : -$offset;
        }
        return $epoch;
    }
    if ($text =~ /\A(\d{4})-(\d{2})-(\d{2})\z/) {
        require Time::Local;
        return Time::Local::timegm(0, 0, 0, $3, $2 - 1, $1);
    }
    return;
}

sub _dictionary_date_epoch {
    my ($dictionary) = @_;
    my $keys = $dictionary->keyEnumerator();
    while (my $key_object = $keys->nextObject()) {
        last unless _valid_object($key_object);
        my $key = objc_string($key_object);
        next unless $key =~ /install.*date|date.*install/i;
        my $epoch = _date_epoch($dictionary->objectForKey_($key_object));
        return $epoch if defined $epoch;
    }
    return;
}

sub _contains_mdm_payload {
    my ($object) = @_;
    return 0 unless _valid_object($object);

    if ($object->isKindOfClass_(NSDictionary->class())) {
        my $keys = $object->keyEnumerator();
        while (my $key_object = $keys->nextObject()) {
            last unless _valid_object($key_object);
            my $value = $object->objectForKey_($key_object);
            my $key = objc_string($key_object);
            my $text = objc_string($value);
            return 1 if $key =~ /payload.*type/i
                && $text eq 'com.apple.mdm';
            return 1 if _contains_mdm_payload($value);
        }
        return 0;
    }

    if ($object->isKindOfClass_(NSArray->class())) {
        my $items = $object->objectEnumerator();
        while (my $item = $items->nextObject()) {
            last unless _valid_object($item);
            return 1 if _contains_mdm_payload($item);
        }
        return 0;
    }

    return 0;
}

sub _mdm_install_epoch_in_object {
    my ($object) = @_;
    return unless _valid_object($object);

    if ($object->isKindOfClass_(NSDictionary->class())) {
        my $date_epoch = _dictionary_date_epoch($object);
        return $date_epoch
            if defined($date_epoch) && _contains_mdm_payload($object);

        my $keys = $object->keyEnumerator();
        while (my $key_object = $keys->nextObject()) {
            last unless _valid_object($key_object);
            my $found = _mdm_install_epoch_in_object(
                $object->objectForKey_($key_object)
            );
            return $found if defined $found;
        }
        return;
    }

    if ($object->isKindOfClass_(NSArray->class())) {
        my $items = $object->objectEnumerator();
        while (my $item = $items->nextObject()) {
            last unless _valid_object($item);
            my $found = _mdm_install_epoch_in_object($item);
            return $found if defined $found;
        }
        return;
    }
    return;
}

sub _iso_utc {
    my ($epoch) = @_;
    return '' unless defined $epoch;
    return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($epoch));
}

sub mdm_install {
    my (%options) = @_;
    my ($ok, $output);
    if (defined $options{profile_output}) {
        ($ok, $output) = (1, $options{profile_output});
    } elsif ($options{profile_probe}) {
        ($ok, $output) = $options{profile_probe}->();
    } else {
        ($ok, $output) = run_command(
            {}, '/usr/sbin/system_profiler', '-xml',
            'SPConfigurationProfileDataType'
        );
    }
    return ('', 0) unless $ok;
    my $plist = parse_plist_output($output);
    my $epoch = _mdm_install_epoch_in_object($plist);
    return ('', 0) unless defined $epoch;

    my $now = defined($options{now}) ? $options{now} : time();
    my $hours = int(($now - $epoch) / 3600);
    $hours = 0 if $hours < 0;
    return (_iso_utc($epoch), $hours);
}

sub perls {
    my ($install_date, $hours_since_install) = mdm_install();
    return {
        mdm_install_date => perl_string($install_date),
        mdm_hours_since_install => perl_integer($hours_since_install),
    };
}
1;
