use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_bool);
use MunkiPerls::Upgrade qw(cached_hardware_snapshot evaluate_upgrade_perls);

sub perls {
    my ($context) = @_;
    my $snapshot = cached_hardware_snapshot($context->{output_path});
    my $results = evaluate_upgrade_perls($snapshot);
    return { map { $_ => perl_bool($results->{$_}) } keys %{$results} };
}
1;
