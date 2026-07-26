use 5.008006;
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use MunkiPerls qw(perl_integer run_command);

sub _identifier_from_ioreg {
    my ($output) = @_;
    return unless defined $output;

    my ($serial) = $output =~ /"IOPlatformSerialNumber"\s*=\s*"([^"]+)"/;
    return $serial if defined($serial) && length($serial);

    my ($uuid) = $output =~ /"IOPlatformUUID"\s*=\s*"([^"]+)"/;
    return $uuid if defined($uuid) && length($uuid);

    return;
}

sub _md5_mod_100 {
    my ($identifier) = @_;
    my $hex = md5_hex($identifier);
    my $mod = 0;
    for my $digit (split //, $hex) {
        $mod = ($mod * 16 + hex($digit)) % 100;
    }
    return $mod;
}

sub shard_for_identifier {
    my ($identifier) = @_;
    return 99 unless defined($identifier) && length($identifier);
    return _md5_mod_100($identifier) + 1;
}

sub shard {
    my (%options) = @_;
    my ($ok, $output);
    if (defined $options{ioreg_output}) {
        ($ok, $output) = (1, $options{ioreg_output});
    } elsif ($options{ioreg_probe}) {
        ($ok, $output) = $options{ioreg_probe}->();
    } else {
        ($ok, $output) = run_command(
            {}, '/usr/sbin/ioreg', '-rd1', '-c',
            'IOPlatformExpertDevice'
        );
    }
    return 99 unless $ok;
    return shard_for_identifier(_identifier_from_ioreg($output));
}

sub perls {
    return { shard => perl_integer(shard()) };
}
1;
