use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(perl_array);

sub local_user_dirs {
    my ($users_path) = @_;
    $users_path ||= '/Users';
    opendir(my $directory, $users_path) or return ();
    my @entries = grep {
        $_ !~ /\A\./
            && $_ ne 'Deleted Users'
            && $_ ne 'Shared'
            && $_ ne 'admin'
    } readdir($directory);
    closedir $directory;
    return sort @entries;
}

sub perls {
    return { local_user_dirs => perl_array(local_user_dirs()) };
}
1;
