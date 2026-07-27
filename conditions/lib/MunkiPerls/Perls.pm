package MunkiPerls::Perls;

use 5.008006;
use strict;
use warnings;

use Exporter qw(import);
use MunkiPerls qw(run_command);

our @EXPORT_OK = qw(
    command_status console_user_perls
);

sub console_user_perls {
    my ($console_path) = @_;
    $console_path ||= '/dev/console';
    my @metadata = stat($console_path);
    my $username = '';
    if (@metadata) {
        my ($name) = getpwuid($metadata[4]);
        $username = $name if defined $name;
    }
    my $logged_in = $username !~ /\A(?:|root|loginwindow|_mbsetupuser)\z/;
    return ($username, $logged_in ? 1 : 0);
}

sub command_status {
    my (@command) = @_;
    my ($ok, $output) = run_command({}, @command);
    return 'Unknown' unless $ok;
    $output =~ s/[\r\n]+\z//;
    return length($output) ? $output : 'Unknown';
}

1;
