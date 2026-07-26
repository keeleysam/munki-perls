#!/usr/bin/perl
use 5.008006;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use MunkiPerls::Plugins qw(run_plugins_condition);

exit run_plugins_condition(
    \@ARGV,
    plugin_dir => "$FindBin::Bin/perls",
);
