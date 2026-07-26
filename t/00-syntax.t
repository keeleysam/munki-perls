use 5.008006;
use strict;
use warnings;

use File::Find;
use Test::More 'no_plan';

my @files;
find(
    sub {
        push @files, $File::Find::name
            if -f $_ && /\.(?:pl|pm|t)\z/;
    },
    'conditions', 'tools', 't'
);

for my $file (sort @files) {
    my $status = system {
        $^X
    } $^X, '-Iconditions/lib', '-c', $file;
    is($status, 0, "$file compiles");
}
