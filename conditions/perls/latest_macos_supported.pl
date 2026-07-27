use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_bool);
use MunkiPerls::Upgrade qw(cached_hardware_snapshot latest_macos_supported);
sub perls {
    my ($context) = @_;
    my $snapshot = cached_hardware_snapshot($context->{output_path});
    return { latest_macos_supported => perl_bool(latest_macos_supported($snapshot)) };
}
1;
