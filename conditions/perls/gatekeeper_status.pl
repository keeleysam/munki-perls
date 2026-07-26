use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
use MunkiPerls::Perls qw(command_status);
sub perls {
    return {
        gatekeeper_status => perl_string(
            command_status('/usr/sbin/spctl', '--status')
        )
    };
}
1;
