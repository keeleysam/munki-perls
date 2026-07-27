use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
use MunkiPerls::Upgrade qw(cached_hardware_snapshot highest_supported_macos_version);
sub perls {
    my ($context) = @_;
    my $snapshot = cached_hardware_snapshot($context->{output_path});
    return { highest_supported_macos_version => perl_string(highest_supported_macos_version($snapshot)) };
}
1;
