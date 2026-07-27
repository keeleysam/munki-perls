use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_string);
use MunkiPerls::Upgrade qw(cached_hardware_snapshot);

sub physical_or_virtual {
    my ($snapshot) = @_;
    return $snapshot->{is_virtual} ? 'virtual' : 'physical';
}

sub perls {
    my ($context) = @_;
    my $snapshot = cached_hardware_snapshot($context->{output_path});
    return { physical_or_virtual => perl_string(
        physical_or_virtual($snapshot)
    ) };
}
1;
