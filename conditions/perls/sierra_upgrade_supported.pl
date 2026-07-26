use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_bool);
use MunkiPerls::Upgrade qw(cached_hardware_snapshot evaluate_upgrade_perl);
my $key = 'sierra_upgrade_supported';
sub perls {
    my ($context) = @_;
    my $snapshot = cached_hardware_snapshot($context->{output_path});
    return { $key => perl_bool(evaluate_upgrade_perl($key, $snapshot)) };
}
1;
