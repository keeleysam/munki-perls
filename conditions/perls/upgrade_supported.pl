use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_bool perl_string);
use MunkiPerls::Upgrade qw(
    cached_hardware_snapshot evaluate_upgrade_perls
    highest_supported_macos_version latest_macos_supported
);

sub perls {
    my ($context) = @_;
    my $snapshot = cached_hardware_snapshot($context->{output_path});
    my $results = evaluate_upgrade_perls($snapshot);
    my %perls = map { $_ => perl_bool($results->{$_}) } keys %{$results};
    $perls{latest_macos_supported} =
        perl_bool(latest_macos_supported($snapshot));
    $perls{highest_supported_macos_version} =
        perl_string(highest_supported_macos_version($snapshot));
    return \%perls;
}
1;
