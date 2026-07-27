use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_bool);
use MunkiPerls::Perls qw(console_user_perls);
sub perls {
    my (undef, $logged_in) = console_user_perls();
    return { console_user_logged_in => perl_bool($logged_in) };
}
1;
