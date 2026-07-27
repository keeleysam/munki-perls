use 5.008006;
use strict;
use warnings;
use Scalar::Util qw(blessed);
use Foundation;
use MunkiPerls qw(
    foundation_string load_plist_file objc_string perl_array
);

sub _valid_object {
    my ($object) = @_;
    return blessed($object) && $$object;
}

sub system_extensions {
    my ($database_path) = @_;
    $database_path ||= '/Library/SystemExtensions/db.plist';

    my $database = load_plist_file($database_path, dictionary => 1);
    return () unless _valid_object($database);

    my $extensions = eval {
        $database->objectForKey_(foundation_string('extensions'));
    };
    return () unless _valid_object($extensions)
        && $extensions->isKindOfClass_(NSArray->class());

    my %enabled;
    for (my $index = 0; $index < $extensions->count(); $index++) {
        my $row = eval { $extensions->objectAtIndex_($index) };
        next unless _valid_object($row)
            && $row->isKindOfClass_(NSDictionary->class());

        my $state = eval {
            $row->objectForKey_(foundation_string('state'));
        };
        next unless _valid_object($state)
            && $state->isKindOfClass_(NSString->class())
            && objc_string($state) eq 'activated_enabled';

        my $identifier = eval {
            $row->objectForKey_(foundation_string('identifier'));
        };
        next unless _valid_object($identifier)
            && $identifier->isKindOfClass_(NSString->class());
        my $bundle_id = objc_string($identifier);
        $enabled{$bundle_id} = 1 if length $bundle_id;
    }

    return sort keys %enabled;
}

sub _array_strings {
    my ($array) = @_;
    return () unless _valid_object($array)
        && $array->isKindOfClass_(NSArray->class());

    my @strings;
    my $items = $array->objectEnumerator();
    while (my $item = $items->nextObject()) {
        last unless _valid_object($item);
        my $text = objc_string($item);
        push @strings, $text if length $text;
    }
    return @strings;
}

sub _policy_mapping {
    my ($policy, $key) = @_;
    my $mapping = eval {
        $policy->objectForKey_(foundation_string($key));
    };
    return unless _valid_object($mapping)
        && $mapping->isKindOfClass_(NSDictionary->class());
    return $mapping;
}

sub _add_policy_mapping {
    my ($mapping, $bundle_ids, $team_ids, $combined) = @_;
    return unless _valid_object($mapping);

    my $teams = $mapping->keyEnumerator();
    while (my $team_object = $teams->nextObject()) {
        last unless _valid_object($team_object);
        my $team_id = objc_string($team_object);
        next unless length $team_id;
        $team_ids->{$team_id} = 1;

        my $bundles = $mapping->objectForKey_($team_object);
        for my $bundle_id (_array_strings($bundles)) {
            $bundle_ids->{$bundle_id} = 1;
            $combined->{"$team_id:$bundle_id"} = 1;
        }
    }
}

sub approved_system_extension_policy {
    my ($database_path) = @_;
    $database_path ||= '/Library/SystemExtensions/db.plist';

    my $database = load_plist_file($database_path, dictionary => 1);
    return ([], [], []) unless _valid_object($database);

    my $policies = eval {
        $database->objectForKey_(foundation_string('extensionPolicies'));
    };
    return ([], [], []) unless _valid_object($policies)
        && $policies->isKindOfClass_(NSArray->class());

    my (%bundle_ids, %team_ids, %combined);
    for (my $index = 0; $index < $policies->count(); $index++) {
        my $policy = eval { $policies->objectAtIndex_($index) };
        next unless _valid_object($policy)
            && $policy->isKindOfClass_(NSDictionary->class());

        for my $team_id (_array_strings(
            $policy->objectForKey_(foundation_string('allowedTeamIDs'))
        )) {
            $team_ids{$team_id} = 1;
        }

        _add_policy_mapping(
            _policy_mapping($policy, 'allowedExtensions'),
            \%bundle_ids, \%team_ids, \%combined
        );

        # Type-only approvals do not name bundle IDs, but the team IDs are
        # still useful policy keys.
        _add_policy_mapping(
            _policy_mapping($policy, 'allowedExtensionTypes'),
            {}, \%team_ids, {}
        );
    }

    return (
        [sort keys %bundle_ids],
        [sort keys %team_ids],
        [sort keys %combined],
    );
}

sub perls {
    my ($bundle_ids, $team_ids, $approved) =
        approved_system_extension_policy();
    return {
        system_extensions => perl_array(system_extensions()),
        approved_system_extension_bundle_ids => perl_array(@{$bundle_ids}),
        approved_system_extension_team_ids => perl_array(@{$team_ids}),
        approved_system_extensions => perl_array(@{$approved}),
    };
}
1;
