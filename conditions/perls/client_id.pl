use 5.008006;
use strict;
use warnings;
use Scalar::Util qw(blessed);
use Foundation;
use MunkiPerls qw(foundation_string objc_string perl_string);

sub _valid_object {
    my ($object) = @_;
    return blessed($object) && $$object;
}

sub client_id {
    my (%options) = @_;
    my $domain = $options{domain};
    if (!_valid_object($domain)) {
        my $defaults = eval { NSUserDefaults->standardUserDefaults() };
        return '' unless _valid_object($defaults);
        $domain = eval {
            $defaults->persistentDomainForName_(
                foundation_string('ManagedInstalls')
            );
        };
    }
    return '' unless _valid_object($domain)
        && $domain->isKindOfClass_(NSDictionary->class());

    my $value = eval {
        $domain->objectForKey_(foundation_string('ClientIdentifier'));
    };
    return objc_string($value);
}

sub perls {
    return { client_id => perl_string(client_id()) };
}
1;
