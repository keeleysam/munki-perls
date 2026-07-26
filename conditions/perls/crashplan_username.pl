use 5.008006;
use strict;
use warnings;
use Encode qw(decode FB_DEFAULT);
use MunkiPerls qw(perl_string);

sub crashplan_username {
    my ($path) = @_;
    $path ||= '/Library/Application Support/CrashPlan/.identity';
    open(my $identity, '<', $path) or return '';
    binmode $identity;
    while (my $line = <$identity>) {
        next unless $line =~ /\Ausername=(.*)\z/s;
        my $username = $1;
        $username =~ s/\s+\z//;
        close $identity;
        return decode('UTF-8', $username, FB_DEFAULT);
    }
    close $identity;
    return '';
}

sub perls {
    return { crashplan_username => perl_string(crashplan_username()) };
}
1;
