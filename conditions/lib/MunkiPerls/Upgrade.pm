package MunkiPerls::Upgrade;

use 5.008006;
use strict;
use warnings;

use Exporter qw(import);
use Fcntl qw(:DEFAULT :flock);
use Scalar::Util qw(blessed);

use MunkiPerls qw(
    foundation_dictionary foundation_string load_plist_file objc_string
    parse_plist_output run_command system_profiler_snapshot system_version
    write_plist_file
);

our @EXPORT_OK = qw(
    cached_hardware_snapshot collect_hardware_snapshot
    evaluate_upgrade_perl evaluate_upgrade_perls
    is_version_at_least version_compare
);

use constant HARDWARE_CACHE_SCHEMA_VERSION => 1;
use constant NS_PROPERTY_LIST_XML_FORMAT_V1_0 => 100;

my @RELEASES = (
    {
        name => 'sierra',
        version => '10.12',
        minimum_from_version => '10.7.5',
        allow => [
            { type => 'model', values => {
                'MacBook6,1' => 1, 'MacBook7,1' => 1, 'MacBook8,1' => 1, 'MacBook9,1' => 1,
                'MacBookAir3,1' => 1, 'MacBookAir3,2' => 1, 'MacBookAir4,1' => 1, 'MacBookAir4,2' => 1,
                'MacBookAir5,1' => 1, 'MacBookAir5,2' => 1, 'MacBookAir6,1' => 1, 'MacBookAir6,2' => 1,
                'MacBookAir7,1' => 1, 'MacBookAir7,2' => 1,
                'MacBookPro10,1' => 1, 'MacBookPro10,2' => 1, 'MacBookPro11,1' => 1, 'MacBookPro11,2' => 1,
                'MacBookPro11,3' => 1, 'MacBookPro11,4' => 1, 'MacBookPro11,5' => 1, 'MacBookPro12,1' => 1,
                'MacBookPro13,1' => 1, 'MacBookPro13,2' => 1, 'MacBookPro13,3' => 1,
                'MacBookPro6,1' => 1, 'MacBookPro6,2' => 1, 'MacBookPro7,1' => 1,
                'MacBookPro8,1' => 1, 'MacBookPro8,2' => 1, 'MacBookPro8,3' => 1,
                'MacBookPro9,1' => 1, 'MacBookPro9,2' => 1,
                'MacPro4,1' => 1, 'MacPro5,1' => 1, 'MacPro6,1' => 1,
                'Macmini4,1' => 1, 'Macmini5,1' => 1, 'Macmini5,2' => 1, 'Macmini5,3' => 1,
                'Macmini6,1' => 1, 'Macmini6,2' => 1, 'Macmini7,1' => 1,
                'iMac10,1' => 1, 'iMac11,1' => 1, 'iMac11,2' => 1, 'iMac11,3' => 1,
                'iMac12,1' => 1, 'iMac12,2' => 1, 'iMac13,1' => 1, 'iMac13,2' => 1, 'iMac13,3' => 1,
                'iMac14,1' => 1, 'iMac14,2' => 1, 'iMac14,3' => 1, 'iMac14,4' => 1,
                'iMac15,1' => 1, 'iMac16,1' => 1, 'iMac16,2' => 1, 'iMac17,1' => 1,
            } },
        ],
    },
    {
        name => 'mojave',
        version => '10.14',
        minimum_from_version => '10.8',
        allow => [
            { type => 'model', values => {
                'MacBook10,1' => 1, 'MacBook8,1' => 1, 'MacBook9,1' => 1,
                'MacBookAir5,1' => 1, 'MacBookAir5,2' => 1, 'MacBookAir6,1' => 1, 'MacBookAir6,2' => 1,
                'MacBookAir7,1' => 1, 'MacBookAir7,2' => 1,
                'MacBookPro10,1' => 1, 'MacBookPro10,2' => 1, 'MacBookPro11,1' => 1, 'MacBookPro11,2' => 1,
                'MacBookPro11,3' => 1, 'MacBookPro11,4' => 1, 'MacBookPro11,5' => 1, 'MacBookPro12,1' => 1,
                'MacBookPro13,1' => 1, 'MacBookPro13,2' => 1, 'MacBookPro13,3' => 1,
                'MacBookPro14,1' => 1, 'MacBookPro14,2' => 1, 'MacBookPro14,3' => 1,
                'MacBookPro15,1' => 1, 'MacBookPro15,2' => 1,
                'MacBookPro9,1' => 1, 'MacBookPro9,2' => 1,
                'MacPro4,1' => 1, 'MacPro6,1' => 1,
                'Macmini6,1' => 1, 'Macmini6,2' => 1, 'Macmini7,1' => 1,
                'iMac13,1' => 1, 'iMac13,2' => 1, 'iMac13,3' => 1,
                'iMac14,1' => 1, 'iMac14,2' => 1, 'iMac14,3' => 1, 'iMac14,4' => 1,
                'iMac15,1' => 1, 'iMac16,1' => 1, 'iMac16,2' => 1, 'iMac17,1' => 1,
                'iMac18,1' => 1, 'iMac18,2' => 1, 'iMac18,3' => 1, 'iMacPro1,1' => 1,
            } },
            # TODO: MacPro5,1 also requires a Metal-capable GPU upgrade to
            # actually run Mojave. Modeling this needs a new 'gpu_capable'
            # condition type (a gpu_chipset_models snapshot field sourced
            # from system_profiler's SPDisplaysDataType, checked against
            # Apple's published Metal-capable GPU list) - deferred.
            { type => 'model', values => { 'MacPro5,1' => 1 } },
        ],
    },
    {
        name => 'catalina',
        version => '10.15',
        minimum_from_version => '10.9',
        allow => [
            { type => 'model', values => {
                'MacBook10,1' => 1, 'MacBook8,1' => 1, 'MacBook9,1' => 1,
                'MacBookAir5,1' => 1, 'MacBookAir5,2' => 1, 'MacBookAir6,1' => 1, 'MacBookAir6,2' => 1,
                'MacBookAir7,1' => 1, 'MacBookAir7,2' => 1, 'MacBookAir8,1' => 1, 'MacBookAir8,2' => 1,
                'MacBookPro10,1' => 1, 'MacBookPro10,2' => 1, 'MacBookPro11,1' => 1, 'MacBookPro11,2' => 1,
                'MacBookPro11,3' => 1, 'MacBookPro11,4' => 1, 'MacBookPro11,5' => 1, 'MacBookPro12,1' => 1,
                'MacBookPro13,1' => 1, 'MacBookPro13,2' => 1, 'MacBookPro13,3' => 1,
                'MacBookPro14,1' => 1, 'MacBookPro14,2' => 1, 'MacBookPro14,3' => 1,
                'MacBookPro15,1' => 1, 'MacBookPro15,2' => 1, 'MacBookPro15,3' => 1, 'MacBookPro15,4' => 1,
                'MacBookPro9,1' => 1, 'MacBookPro9,2' => 1,
                'MacPro6,1' => 1, 'MacPro7,1' => 1,
                'Macmini6,1' => 1, 'Macmini6,2' => 1, 'Macmini7,1' => 1, 'Macmini8,1' => 1,
                'iMac13,1' => 1, 'iMac13,2' => 1, 'iMac13,3' => 1,
                'iMac14,1' => 1, 'iMac14,2' => 1, 'iMac14,3' => 1, 'iMac14,4' => 1,
                'iMac15,1' => 1, 'iMac16,1' => 1, 'iMac16,2' => 1, 'iMac17,1' => 1,
                'iMac18,1' => 1, 'iMac18,2' => 1, 'iMac18,3' => 1, 'iMac19,1' => 1, 'iMac19,2' => 1,
                'iMacPro1,1' => 1,
            } },
        ],
    },
    {
        name => 'bigsur',
        version => '11',
        minimum_from_version => '10.7', # TODO verify against real Install macOS Big Sur.app LSMinimumSystemVersion
        allow => [
            { type => 'model', values => {
                'MacBook10,1' => 1, 'MacBook8,1' => 1, 'MacBook9,1' => 1,
                'MacBookAir6,1' => 1, 'MacBookAir6,2' => 1, 'MacBookAir7,1' => 1, 'MacBookAir7,2' => 1,
                'MacBookAir8,1' => 1, 'MacBookAir8,2' => 1, 'MacBookAir9,1' => 1,
                'MacBookPro11,2' => 1, 'MacBookPro11,3' => 1, 'MacBookPro11,4' => 1, 'MacBookPro11,5' => 1,
                'MacBookPro12,1' => 1, 'MacBookPro13,1' => 1, 'MacBookPro13,2' => 1, 'MacBookPro13,3' => 1,
                'MacBookPro14,1' => 1, 'MacBookPro14,2' => 1, 'MacBookPro14,3' => 1,
                'MacBookPro15,1' => 1, 'MacBookPro15,2' => 1, 'MacBookPro15,3' => 1, 'MacBookPro15,4' => 1,
                'MacBookPro16,1' => 1, 'MacBookPro16,2' => 1, 'MacBookPro16,3' => 1, 'MacBookPro16,4' => 1,
                'MacPro6,1' => 1, 'MacPro7,1' => 1,
                'Macmini7,1' => 1, 'Macmini8,1' => 1, 'VirtualMac2,1' => 1,
                'iMac14,4' => 1, 'iMac15,1' => 1, 'iMac16,1' => 1, 'iMac16,2' => 1, 'iMac17,1' => 1,
                'iMac18,1' => 1, 'iMac18,2' => 1, 'iMac18,3' => 1, 'iMac19,1' => 1, 'iMac19,2' => 1,
                'iMac20,1' => 1, 'iMac20,2' => 1, 'iMacPro1,1' => 1,
            } },
        ],
    },
    {
        name => 'monterey',
        version => '12',
        minimum_from_version => '10.7', # TODO verify against real Install macOS Monterey.app LSMinimumSystemVersion
        allow => [
            { type => 'model', values => {
                'MacBook10,1' => 1, 'MacBook9,1' => 1,
                'MacBookAir7,1' => 1, 'MacBookAir7,2' => 1, 'MacBookAir8,1' => 1, 'MacBookAir8,2' => 1,
                'MacBookAir9,1' => 1,
                'MacBookPro11,4' => 1, 'MacBookPro11,5' => 1, 'MacBookPro12,1' => 1,
                'MacBookPro13,1' => 1, 'MacBookPro13,2' => 1, 'MacBookPro13,3' => 1,
                'MacBookPro14,1' => 1, 'MacBookPro14,2' => 1, 'MacBookPro14,3' => 1,
                'MacBookPro15,1' => 1, 'MacBookPro15,2' => 1, 'MacBookPro15,3' => 1, 'MacBookPro15,4' => 1,
                'MacBookPro16,1' => 1, 'MacBookPro16,2' => 1, 'MacBookPro16,3' => 1, 'MacBookPro16,4' => 1,
                'MacPro6,1' => 1, 'MacPro7,1' => 1,
                'Macmini7,1' => 1, 'Macmini8,1' => 1, 'VirtualMac2,1' => 1,
                'iMac16,1' => 1, 'iMac16,2' => 1, 'iMac17,1' => 1,
                'iMac18,1' => 1, 'iMac18,2' => 1, 'iMac18,3' => 1, 'iMac19,1' => 1, 'iMac19,2' => 1,
                'iMac20,1' => 1, 'iMac20,2' => 1, 'iMacPro1,1' => 1,
            } },
            { type => 'hardware_target', values => {
                'J132AP' => 1, 'J137AP' => 1, 'J140AAP' => 1, 'J140KAP' => 1, 'J152FAP' => 1,
                'J160AP' => 1, 'J174AP' => 1, 'J185AP' => 1, 'J185FAP' => 1,
                'J213AP' => 1, 'J214AP' => 1, 'J214KAP' => 1, 'J215AP' => 1, 'J223AP' => 1,
                'J230AP' => 1, 'J230KAP' => 1, 'J274AP' => 1, 'J293AP' => 1, 'J313AP' => 1,
                'J314cAP' => 1, 'J314sAP' => 1, 'J316cAP' => 1, 'J316sAP' => 1,
                'J456AP' => 1, 'J457AP' => 1, 'J680AP' => 1, 'J780AP' => 1,
                'VMA2MACOSAP' => 1, 'VMM-x86' => 1, 'X589AMLUAP' => 1, 'X86LEGACYAP' => 1,
            } },
        ],
    },
    {
        name => 'ventura',
        version => '13',
        minimum_from_version => '10.7', # TODO verify against real Install macOS Ventura.app LSMinimumSystemVersion
        allow => [
            { type => 'model', values => {
                'Mac13,1' => 1, 'Mac13,2' => 1, 'Mac14,2' => 1, 'Mac14,7' => 1,
                'MacBook10,1' => 1, 'MacBookAir10,1' => 1,
                'MacBookAir8,1' => 1, 'MacBookAir8,2' => 1, 'MacBookAir9,1' => 1,
                'MacBookPro14,1' => 1, 'MacBookPro14,2' => 1, 'MacBookPro14,3' => 1,
                'MacBookPro15,1' => 1, 'MacBookPro15,2' => 1, 'MacBookPro15,3' => 1, 'MacBookPro15,4' => 1,
                'MacBookPro16,1' => 1, 'MacBookPro16,2' => 1, 'MacBookPro16,3' => 1, 'MacBookPro16,4' => 1,
                'MacBookPro17,1' => 1,
                'MacBookPro18,1' => 1, 'MacBookPro18,2' => 1, 'MacBookPro18,3' => 1, 'MacBookPro18,4' => 1,
                'MacPro7,1' => 1, 'Macmini8,1' => 1, 'Macmini9,1' => 1, 'VirtualMac2,1' => 1,
                'iMac18,1' => 1, 'iMac18,2' => 1, 'iMac18,3' => 1, 'iMac19,1' => 1, 'iMac19,2' => 1,
                'iMac20,1' => 1, 'iMac20,2' => 1, 'iMac21,1' => 1, 'iMac21,2' => 1,
                'iMacPro1,1' => 1, 'iSim1,1' => 1,
            } },
        ],
    },
    {
        name => 'sonoma',
        version => '14',
        minimum_from_version => '10.7', # TODO verify against real Install macOS Sonoma.app LSMinimumSystemVersion
        allow => [
            { type => 'model', values => {
                'Mac13,1' => 1, 'Mac13,2' => 1,
                'Mac14,10' => 1, 'Mac14,12' => 1, 'Mac14,13' => 1, 'Mac14,14' => 1, 'Mac14,15' => 1,
                'Mac14,2' => 1, 'Mac14,3' => 1, 'Mac14,5' => 1, 'Mac14,6' => 1, 'Mac14,7' => 1,
                'Mac14,8' => 1, 'Mac14,9' => 1,
                'Mac15,3' => 1, 'Mac15,4' => 1, 'Mac15,5' => 1, 'Mac15,6' => 1, 'Mac15,7' => 1,
                'Mac15,8' => 1, 'Mac15,9' => 1,
                'MacBookAir10,1' => 1, 'MacBookAir8,1' => 1, 'MacBookAir8,2' => 1, 'MacBookAir9,1' => 1,
                'MacBookPro15,1' => 1, 'MacBookPro15,2' => 1, 'MacBookPro15,3' => 1, 'MacBookPro15,4' => 1,
                'MacBookPro16,1' => 1, 'MacBookPro16,2' => 1, 'MacBookPro16,3' => 1, 'MacBookPro16,4' => 1,
                'MacBookPro17,1' => 1,
                'MacBookPro18,1' => 1, 'MacBookPro18,2' => 1, 'MacBookPro18,3' => 1, 'MacBookPro18,4' => 1,
                'MacPro7,1' => 1, 'Macmini8,1' => 1, 'Macmini9,1' => 1, 'VirtualMac2,1' => 1,
                'iMac19,1' => 1, 'iMac19,2' => 1, 'iMac20,1' => 1, 'iMac20,2' => 1,
                'iMac21,1' => 1, 'iMac21,2' => 1, 'iMacPro1,1' => 1, 'iSim1,1' => 1,
            } },
        ],
    },
    {
        name => 'sequoia',
        version => '15',
        minimum_from_version => '10.7', # TODO verify against real Install macOS Sequoia.app LSMinimumSystemVersion
        allow => [
            { type => 'model', values => {
                'Mac13,1' => 1, 'Mac13,2' => 1,
                'Mac14,10' => 1, 'Mac14,12' => 1, 'Mac14,13' => 1, 'Mac14,14' => 1, 'Mac14,15' => 1,
                'Mac14,2' => 1, 'Mac14,3' => 1, 'Mac14,5' => 1, 'Mac14,6' => 1, 'Mac14,7' => 1,
                'Mac14,8' => 1, 'Mac14,9' => 1,
                'Mac15,10' => 1, 'Mac15,11' => 1, 'Mac15,12' => 1, 'Mac15,13' => 1,
                'Mac15,3' => 1, 'Mac15,4' => 1, 'Mac15,5' => 1, 'Mac15,6' => 1, 'Mac15,7' => 1,
                'Mac15,8' => 1, 'Mac15,9' => 1,
                'MacBookAir10,1' => 1, 'MacBookAir9,1' => 1,
                'MacBookPro15,1' => 1, 'MacBookPro15,2' => 1, 'MacBookPro15,3' => 1, 'MacBookPro15,4' => 1,
                'MacBookPro16,1' => 1, 'MacBookPro16,2' => 1, 'MacBookPro16,3' => 1, 'MacBookPro16,4' => 1,
                'MacBookPro17,1' => 1,
                'MacBookPro18,1' => 1, 'MacBookPro18,2' => 1, 'MacBookPro18,3' => 1, 'MacBookPro18,4' => 1,
                'MacPro7,1' => 1, 'Macmini8,1' => 1, 'Macmini9,1' => 1, 'VirtualMac2,1' => 1,
                'iMac19,1' => 1, 'iMac19,2' => 1, 'iMac20,1' => 1, 'iMac20,2' => 1,
                'iMac21,1' => 1, 'iMac21,2' => 1, 'iMacPro1,1' => 1,
            } },
        ],
    },
    {
        name => 'tahoe',
        version => '26',
        minimum_from_version => '10.7', # TODO verify against real Install macOS Tahoe.app LSMinimumSystemVersion
        allow => [
            { type => 'model', values => {
                'Mac13,1' => 1, 'Mac13,2' => 1,
                'Mac14,10' => 1, 'Mac14,12' => 1, 'Mac14,13' => 1, 'Mac14,14' => 1, 'Mac14,15' => 1,
                'Mac14,2' => 1, 'Mac14,3' => 1, 'Mac14,5' => 1, 'Mac14,6' => 1, 'Mac14,7' => 1,
                'Mac14,8' => 1, 'Mac14,9' => 1,
                'Mac15,10' => 1, 'Mac15,11' => 1, 'Mac15,12' => 1, 'Mac15,13' => 1, 'Mac15,14' => 1,
                'Mac15,3' => 1, 'Mac15,4' => 1, 'Mac15,5' => 1, 'Mac15,6' => 1, 'Mac15,7' => 1,
                'Mac15,8' => 1, 'Mac15,9' => 1,
                'Mac16,1' => 1, 'Mac16,10' => 1, 'Mac16,11' => 1, 'Mac16,12' => 1, 'Mac16,13' => 1,
                'Mac16,15' => 1, 'Mac16,2' => 1, 'Mac16,3' => 1, 'Mac16,5' => 1, 'Mac16,6' => 1,
                'Mac16,7' => 1, 'Mac16,8' => 1, 'Mac16,9' => 1,
                'MacBookAir10,1' => 1,
                'MacBookPro16,1' => 1, 'MacBookPro16,2' => 1, 'MacBookPro16,4' => 1, 'MacBookPro17,1' => 1,
                'MacBookPro18,1' => 1, 'MacBookPro18,2' => 1, 'MacBookPro18,3' => 1, 'MacBookPro18,4' => 1,
                'MacPro7,1' => 1, 'Macmini9,1' => 1, 'VirtualMac2,1' => 1,
                'iMac20,1' => 1, 'iMac20,2' => 1, 'iMac21,1' => 1, 'iMac21,2' => 1,
            } },
        ],
    },
    {
        name => 'goldengate',
        version => '27',
        minimum_from_version => '10.7', # TODO verify against real Install macOS Goldengate.app LSMinimumSystemVersion
        allow => [
            { type => 'hardware_target', values => {
                'J180dAP' => 1, 'J274AP' => 1, 'J293AP' => 1, 'J313AP' => 1,
                'J314cAP' => 1, 'J314sAP' => 1, 'J316cAP' => 1, 'J316sAP' => 1,
                'J375cAP' => 1, 'J375dAP' => 1,
                'J413AP' => 1, 'J414cAP' => 1, 'J414sAP' => 1, 'J415AP' => 1,
                'J416cAP' => 1, 'J416sAP' => 1, 'J433AP' => 1, 'J434AP' => 1,
                'J456AP' => 1, 'J457AP' => 1, 'J473AP' => 1, 'J474sAP' => 1,
                'J475cAP' => 1, 'J475dAP' => 1, 'J493AP' => 1, 'J504AP' => 1,
                'J514cAP' => 1, 'J514mAP' => 1, 'J514sAP' => 1,
                'J516cAP' => 1, 'J516mAP' => 1, 'J516sAP' => 1,
                'J575cAP' => 1, 'J575dAP' => 1, 'J604AP' => 1, 'J613AP' => 1,
                'J614cAP' => 1, 'J614sAP' => 1, 'J615AP' => 1,
                'J616cAP' => 1, 'J616sAP' => 1, 'J623AP' => 1, 'J624AP' => 1,
                'J700AP' => 1, 'J704AP' => 1, 'J713AP' => 1,
                'J714cAP' => 1, 'J714sAP' => 1, 'J715AP' => 1,
                'J716cAP' => 1, 'J716sAP' => 1, 'J773gAP' => 1, 'J773sAP' => 1,
                'J813AP' => 1, 'J815AP' => 1, 'VMA2MACOSAP' => 1,
            } },
        ],
    },
);

sub _version_parts {
    my ($version) = @_;
    return unless defined $version && $version =~ /\A(\d+)(?:\.(\d+))?(?:\.(\d+))?/;
    return ($1 + 0, defined($2) ? $2 + 0 : 0, defined($3) ? $3 + 0 : 0);
}

sub version_compare {
    my ($left, $right) = @_;
    my @left = _version_parts($left);
    my @right = _version_parts($right);
    return unless @left && @right;
    for my $index (0 .. 2) {
        return -1 if $left[$index] < $right[$index];
        return 1 if $left[$index] > $right[$index];
    }
    return 0;
}

sub is_version_at_least {
    my ($version, $minimum) = @_;
    my $comparison = version_compare($version, $minimum);
    return defined($comparison) && $comparison >= 0 ? 1 : 0;
}

# Recursively search a parsed plist tree for the first string (or
# string-convertible) value under the given key, wherever it appears.
# Mirrors virtual_type.pl's own tree walk: system_profiler's XML shape
# nests the field we want a few levels deep, and searching generically
# is more robust across OS versions than hardcoding that exact path.
sub _string_for_key_in_object {
    my ($object, $wanted_key) = @_;
    return '' unless blessed($object) && $$object;

    if ($object->isKindOfClass_(NSDictionary->class())) {
        my $keys = $object->keyEnumerator();
        while (my $key_object = $keys->nextObject()) {
            last unless blessed($key_object) && $$key_object;
            my $value = $object->objectForKey_($key_object);
            if (objc_string($key_object) eq $wanted_key) {
                my $text = objc_string($value);
                return $text if length $text;
            }
            my $found = _string_for_key_in_object($value, $wanted_key);
            return $found if length $found;
        }
        return '';
    }

    if ($object->isKindOfClass_(NSArray->class())) {
        my $items = $object->objectEnumerator();
        while (my $item = $items->nextObject()) {
            last unless blessed($item) && $$item;
            my $found = _string_for_key_in_object($item, $wanted_key);
            return $found if length $found;
        }
        return '';
    }
    return '';
}

sub _sysctl {
    my ($name) = @_;
    my ($ok, $output) = run_command(
        {}, '/usr/sbin/sysctl', '-n', $name
    );
    return '' unless $ok;
    $output =~ s/[\r\n]+\z//;
    return $output;
}

sub _cpu_type_name {
    my ($cputype) = @_;
    return 'powerpc' if $cputype eq '18';
    return 'intel' if $cputype eq '7' || $cputype eq '16777223';
    return 'arm' if $cputype eq '12' || $cputype eq '16777228';
    return '';
}

sub _cpu_family_name {
    my ($cpu_type, $cpusubtype) = @_;
    return '' unless $cpu_type eq 'powerpc';
    return 'g3' if $cpusubtype eq '9';
    return 'g4' if $cpusubtype eq '10' || $cpusubtype eq '11';
    return 'g5' if $cpusubtype eq '100' || $cpusubtype eq '101' || $cpusubtype eq '102';
    return '';
}

sub collect_hardware_snapshot {
    my (%options) = @_;
    my $version = defined($options{version})
        ? $options{version}
        : system_version($options{system_version_path});

    # machine_model comes from the system_profiler call every plugin
    # already shares (see system_profiler_snapshot in MunkiPerls.pm)
    # rather than ioreg: system_profiler derives it from the same
    # underlying IOKit property, so this works identically on every OS
    # version with no extra process spawned beyond the one
    # system_profiler_snapshot() already makes. board-id is dropped
    # entirely - no confirmed evidence it ever diverges from model in
    # outcome for any machine in this table, so there is no longer any
    # ioreg call in this function at all.
    my ($profiler_ok, $profiler_output);
    if (defined $options{profiler_output}) {
        ($profiler_ok, $profiler_output) = (1, $options{profiler_output});
    } else {
        ($profiler_ok, $profiler_output) = system_profiler_snapshot();
    }
    my $model = $profiler_ok
        ? _string_for_key_in_object(
            parse_plist_output($profiler_output), 'machine_model'
        )
        : '';

    my $sysctl = sub {
        my ($name) = @_;
        if (ref($options{sysctl_values}) eq 'HASH'
                && exists $options{sysctl_values}{$name}) {
            return $options{sysctl_values}{$name};
        }
        return _sysctl($name);
    };

    my $hardware_target = defined($options{hardware_target})
        ? $options{hardware_target}
        : $sysctl->('hw.target');

    my $cpu_type = defined($options{cpu_type})
        ? $options{cpu_type}
        : _cpu_type_name($sysctl->('hw.cputype'));
    my $cpu_family = defined($options{cpu_family})
        ? $options{cpu_family}
        : _cpu_family_name($cpu_type, $sysctl->('hw.cpusubtype'));
    my $cpu_64bit = defined($options{cpu_64bit})
        ? $options{cpu_64bit}
        : ($sysctl->('hw.cpu64bit_capable') =~ /\A[1-9]\d*\z/ ? 1 : 0);
    my $cpu_frequency_mhz = defined($options{cpu_frequency_mhz})
        ? $options{cpu_frequency_mhz}
        : int(($sysctl->('hw.cpufrequency') || 0) / 1_000_000);
    my $ram_mb = defined($options{ram_mb})
        ? $options{ram_mb}
        : int(($sysctl->('hw.memsize') || 0) / (1024 * 1024));

    my $virtual;
    if (defined $options{is_virtual}) {
        $virtual = $options{is_virtual} ? 1 : 0;
    } elsif (is_version_at_least($version, '11')) {
        my $present = $sysctl->('kern.hv_vmm_present');
        $virtual = $present =~ /\A[1-9]\d*\z/ ? 1 : 0;
    } else {
        my $features = $sysctl->('machdep.cpu.features');
        $virtual = $features =~ /(?:\A|\s)VMM(?:\s|\z)/ ? 1 : 0;
    }

    return {
        version => $version,
        model => $model,
        hardware_target => $hardware_target,
        cpu_type => $cpu_type,
        cpu_family => $cpu_family,
        cpu_64bit => $cpu_64bit,
        cpu_frequency_mhz => $cpu_frequency_mhz,
        ram_mb => $ram_mb,
        is_virtual => $virtual,
    };
}

sub _boot_identifier {
    my (%options) = @_;
    my $identifier;
    if (exists $options{boot_identifier}) {
        $identifier = $options{boot_identifier};
    } elsif ($options{boot_probe}) {
        $identifier = $options{boot_probe}->();
    } else {
        $identifier = _sysctl('kern.boottime');
    }
    return '' unless defined $identifier;
    $identifier =~ s/[\r\n]+\z//;
    return $identifier;
}

sub _cache_string {
    my ($cache, $key) = @_;
    my $value = eval {
        $cache->objectForKey_(foundation_string($key));
    };
    return unless blessed($value) && $$value;
    return unless $value->isKindOfClass_(NSString->class());
    return objc_string($value);
}

sub _snapshot_from_cache {
    my ($path, $boot_identifier) = @_;
    my $cache = load_plist_file($path, dictionary => 1);
    return unless blessed($cache) && $$cache;

    my $schema = eval {
        $cache->objectForKey_(foundation_string('schema_version'));
    };
    return unless blessed($schema) && $$schema;
    return unless $schema->isKindOfClass_(NSNumber->class());
    return unless $schema->intValue() == HARDWARE_CACHE_SCHEMA_VERSION;

    my $cached_boot = _cache_string($cache, 'boot_identifier');
    return unless defined($cached_boot) && $cached_boot eq $boot_identifier;

    my %snapshot;
    for my $key (qw(version model hardware_target cpu_type cpu_family cpu_64bit cpu_frequency_mhz ram_mb)) {
        my $value = _cache_string($cache, $key);
        return unless defined $value;
        $snapshot{$key} = $value;
    }
    my $virtual = eval {
        $cache->objectForKey_(foundation_string('is_virtual'));
    };
    return unless blessed($virtual) && $$virtual;
    return unless $virtual->isKindOfClass_(NSNumber->class());
    $snapshot{is_virtual} = $virtual->boolValue() ? 1 : 0;
    return \%snapshot;
}

sub _write_snapshot_cache {
    my ($path, $boot_identifier, $snapshot) = @_;
    my $cache = foundation_dictionary();
    $cache->setObject_forKey_(
        NSNumber->numberWithInt_(HARDWARE_CACHE_SCHEMA_VERSION),
        foundation_string('schema_version')
    );
    $cache->setObject_forKey_(
        foundation_string($boot_identifier),
        foundation_string('boot_identifier')
    );
    for my $key (qw(version model hardware_target cpu_type cpu_family cpu_64bit cpu_frequency_mhz ram_mb)) {
        $cache->setObject_forKey_(
            foundation_string(defined($snapshot->{$key}) ? $snapshot->{$key} : ''),
            foundation_string($key)
        );
    }
    $cache->setObject_forKey_(
        NSNumber->numberWithBool_($snapshot->{is_virtual} ? 1 : 0),
        foundation_string('is_virtual')
    );

    my $valid = NSPropertyListSerialization->propertyList_isValidForFormat_(
        $cache, NS_PROPERTY_LIST_XML_FORMAT_V1_0
    );
    return unless $valid;
    return write_plist_file(
        $path, $cache, NS_PROPERTY_LIST_XML_FORMAT_V1_0
    );
}

sub cached_hardware_snapshot {
    my ($output_path, %options) = @_;
    die "Output path is required for hardware caching\n"
        unless defined($output_path) && length($output_path);

    my $collect = $options{collector} || sub {
        return collect_hardware_snapshot(%options);
    };
    my $boot_identifier = _boot_identifier(%options);
    return $collect->() unless length $boot_identifier;

    my $cache_path = $output_path . '.munki-perls-hardware-cache.plist';
    my $lock_path = $cache_path . '.lock';
    my $lock;
    if (!sysopen($lock, $lock_path, O_RDWR | O_CREAT, 0600)) {
        return $collect->();
    }
    if (!flock($lock, LOCK_EX)) {
        close $lock;
        return $collect->();
    }

    my $snapshot = _snapshot_from_cache($cache_path, $boot_identifier);
    if (!$snapshot) {
        $snapshot = $collect->();
        my $writer = $options{cache_writer} || \&_write_snapshot_cache;
        eval { $writer->($cache_path, $boot_identifier, $snapshot) };
    }
    close $lock;
    return $snapshot;
}

sub _model_matches {
    my ($condition, $snapshot) = @_;
    my $model = $snapshot->{model} || '';
    return 0 unless length $model;
    return $condition->{values}{$model} ? 1 : 0;
}

sub _hardware_target_matches {
    my ($condition, $snapshot) = @_;
    my $target = $snapshot->{hardware_target} || '';
    return 0 unless length $target;
    return $condition->{values}{$target} ? 1 : 0;
}

sub _cpu_matches {
    my ($condition, $snapshot) = @_;
    return 0 unless ($snapshot->{cpu_type} || '') eq ($condition->{cpu_type} || '');
    if (defined $condition->{cpu_family}) {
        return 0 unless ($snapshot->{cpu_family} || '') eq $condition->{cpu_family};
    }
    if (defined $condition->{min_frequency_mhz}) {
        return 0 unless ($snapshot->{cpu_frequency_mhz} || 0) >= $condition->{min_frequency_mhz};
    }
    if ($condition->{cpu_64bit}) {
        return 0 unless $snapshot->{cpu_64bit};
    }
    return 1;
}

sub _condition_matches {
    my ($condition, $snapshot) = @_;
    if ($condition->{all}) {
        for my $sub_condition (@{$condition->{all}}) {
            return 0 unless _condition_matches($sub_condition, $snapshot);
        }
        return 1;
    }
    my $type = $condition->{type} || '';
    return _model_matches($condition, $snapshot) if $type eq 'model';
    return _hardware_target_matches($condition, $snapshot) if $type eq 'hardware_target';
    return _cpu_matches($condition, $snapshot) if $type eq 'cpu';
    return 0;
}

sub _physical_supported {
    my ($release, $snapshot) = @_;
    for my $condition (@{$release->{allow} || []}) {
        return 1 if _condition_matches($condition, $snapshot);
    }
    return 0;
}

sub evaluate_upgrade_perl {
    my ($key, $snapshot) = @_;
    die "Hardware snapshot must be a hash reference\n"
        unless ref($snapshot) eq 'HASH';
    my $wanted;
    for my $release (@RELEASES) {
        if ($key eq $release->{name} . '_upgrade_supported') {
            $wanted = $release;
            last;
        }
    }
    die "Unknown upgrade perl: $key\n" unless $wanted;

    my $at_target = version_compare(
        $snapshot->{version}, $wanted->{version}
    );
    # minimum_from_version is optional: a release with none imposes no
    # lower bound (any source version below the target is eligible).
    my $at_minimum = defined($wanted->{minimum_from_version})
        ? version_compare($snapshot->{version}, $wanted->{minimum_from_version})
        : 0;

    # Being there already is not, strictly speaking, an upgrade path.
    return 0 if !defined($at_target) || !defined($at_minimum);
    return 0 if $at_target >= 0;
    return 0 if $at_minimum < 0;
    return 1 if $snapshot->{is_virtual};
    return _physical_supported($wanted, $snapshot);
}

sub evaluate_upgrade_perls {
    my ($snapshot) = @_;
    die "Hardware snapshot must be a hash reference\n"
        unless ref($snapshot) eq 'HASH';
    my %perls;
    for my $release (@RELEASES) {
        my $key = $release->{name} . '_upgrade_supported';
        $perls{$key} = evaluate_upgrade_perl($key, $snapshot);
    }
    return \%perls;
}

1;
