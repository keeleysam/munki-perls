use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
use MunkiPerls::Perls qw(command_status);
sub perls {
    return {
        sip_status => perl_string(
            command_status('/usr/bin/csrutil', 'status')
        )
    };
}
1;
