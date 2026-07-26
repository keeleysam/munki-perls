use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_array);

sub admin_users {
    my (undef, undef, undef, $members) = getgrnam('admin');
    return () unless defined $members && length $members;
    return sort grep { length $_ } split /\s+/, $members;
}

sub perls {
    return { admin_users => perl_array(admin_users()) };
}
1;
