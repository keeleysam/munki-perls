use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
use MunkiPerls::Perls qw(console_user_perls);
sub perls {
    my ($username) = console_user_perls();
    return { console_user => perl_string($username) };
}
1;
