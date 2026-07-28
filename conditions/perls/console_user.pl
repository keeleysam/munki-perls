use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_bool perl_string);
use MunkiPerls::Perls qw(console_user_perls);
sub perls {
    my ($username, $logged_in) = console_user_perls();
    return {
        console_user => perl_string($username),
        console_user_logged_in => perl_bool($logged_in),
    };
}
1;
