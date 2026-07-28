<p align="center">
  <img src="assets/logo.png" alt="munki-perls — native Mac perls in classic Perl" width="720">
</p>

<h1 align="center">munki-perls</h1>

<p align="center">
  <strong>Typed Munki perls for Macs from Tiger onward.</strong><br>
  Drop-in plugins, native plist values, and no additional runtime to explain.<br>
  From G3 to M3, from G5 to M5, with Intel holding the middle: it's all supported.
</p>

<p align="center">
  <a href="https://weswhet.github.io/munki-perls/"><strong>Website and quickstart</strong></a>
</p>

<p align="center">
  <a href="https://github.com/weswhet/munki-perls/actions/workflows/test.yml"><img src="https://github.com/weswhet/munki-perls/actions/workflows/test.yml/badge.svg" alt="Test status"></a>
  <a href="https://github.com/weswhet/munki-perls/releases/latest"><img src="https://img.shields.io/github/v/release/weswhet/munki-perls?label=release" alt="Latest release"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/license-Apache--2.0-6f5bd3" alt="Apache 2.0 license"></a>
</p>

> A condition should be interesting to the manifest and profoundly boring to
> the machine.

When a Mac checks in, Munki already knows quite a lot. The difficult question
is usually the one perl it does not know: whether FileVault is on, which user
owns the console, whether the hardware can take the next macOS upgrade, or
what sort of virtual machine has appeared in inventory this morning.

[`munki-facts`](https://github.com/munki/munki-facts) established a useful
vocabulary for those answers. `munki-perls` carries that vocabulary forward as
a Perl 5.8.6-compatible collection of Munki
[admin-provided conditions](https://github.com/munki/munki/wiki/Conditional-Items),
using only the `Foundation` and `PerlObjCBridge` modules Apple shipped with OS X.
It runs on fully patched Mac OS X 10.4.11 Tiger and 10.5.8 Leopard on Intel
and PowerPC, verified on real G5 hardware, all the way through the current
release on the latest Apple Silicon, without installing Python, a package
manager, or a small ecosystem in order to write one property list. PowerPC,
Intel, or Apple Silicon: if Apple shipped a Perl on it, munki-perls runs on
it. Leopard package installation still hasn't been smoke-tested end to end;
see [Testing](#testing) for the validation boundary.

The result is deliberately plain: native plist values, serialized updates, a
strict subprocess allowlist for bundled collectors, and perls that keep their
historical names and semantics. Inventory should be informative. Its
implementation need not be an event.

## At a glance

| | |
| --- | --- |
| **Compatibility** | PowerPC (Tiger/Leopard, verified on real G5 hardware) through Intel through Apple Silicon, on every OS X and macOS release in between; Perl 5.8.6 |
| **Contract** | Drop-in `perls()` plugins returning typed key/value maps |
| **Output** | Munki's configured `ManagedInstallDir/ConditionalItems.plist` |
| **Dependencies** | Apple's stock Perl, `Foundation`, and `PerlObjCBridge` |
| **Writes** | Sidecar-locked and atomically replaced through Foundation |
| **Distribution** | Developer ID-signed `.pkg` from each successful `main` release |

## What it knows

The perls fall into four families. They share one writer and one contract, so
adding an answer does not create a new dialect of “true.”

| Family | Answers |
| --- | --- |
| **People and sessions** | admin users, console user and login state, local home directories, CrashPlan username |
| **Security and management** | FileVault, Gatekeeper, SIP, Back to My Mac, managed user, MDM profile install age, enabled and approved system extensions |
| **Hardware** | physical or virtual, virtual-machine vendor, stable shard |
| **Upgrade paths** | Leopard through Goldengate, evaluated against OS version and Apple hardware identifiers (model, board, or CPU family and speed), plus two always-present hardware-ceiling perls |

### Bundled perl contract

One executable runner discovers the non-executable `.pl` files in its sibling
`perls` directory. Each plugin defines `perls()`, returns one or more typed
keys, and needs no plist-writing or command-line scaffolding. The bundled
plugins provide the following keys and native plist types.

| Key | Native plist type |
| --- | --- |
| `admin_users` | array of strings |
| `approved_system_extension_bundle_ids` | array of strings |
| `approved_system_extension_team_ids` | array of strings |
| `approved_system_extensions` | array of strings: `TEAMID:bundle.id` policy keys |
| `backtomymac_configured` | boolean |
| `bigsur_upgrade_supported` | boolean |
| `catalina_upgrade_supported` | boolean |
| `client_id` | string |
| `console_user` | string |
| `console_user_logged_in` | boolean |
| `crashplan_username` | string |
| `elcapitan_upgrade_supported` | boolean |
| `filevault_status` | string |
| `gatekeeper_status` | string |
| `goldengate_upgrade_supported` | boolean |
| `highest_supported_macos_version` | string: the highest release version this hardware can ever reach, ignoring the current OS version and any RAM minimum |
| `latest_macos_supported` | boolean: whether this hardware can reach the newest release at all, ignoring the current OS version and any RAM minimum |
| `leopard_upgrade_supported` | boolean |
| `lion_upgrade_supported` | boolean |
| `local_user_dirs` | array of strings |
| `mavericks_upgrade_supported` | boolean |
| `mdm_hours_since_install` | integer |
| `mdm_install_date` | string: UTC ISO 8601 timestamp, or empty when unavailable |
| `mdm_managed_user` | string |
| `mojave_upgrade_supported` | boolean |
| `monterey_upgrade_supported` | boolean |
| `mountainlion_upgrade_supported` | boolean |
| `physical_or_virtual` | string: `physical` or `virtual` |
| `sequoia_upgrade_supported` | boolean |
| `shard` | integer: stable value from 1 through 100, or 99 when no hardware identifier is available |
| `sierra_upgrade_supported` | boolean |
| `sip_status` | string |
| `snowleopard_upgrade_supported` | boolean |
| `sonoma_upgrade_supported` | boolean |
| `system_extensions` | array of currently enabled system-extension bundle identifiers |
| `tahoe_upgrade_supported` | boolean |
| `ventura_upgrade_supported` | boolean |
| `virtual_type` | string: empty on physical Macs; `vmware`, `virtualbox`, `parallels`, or `unknown` on virtual Macs |
| `yosemite_upgrade_supported` | boolean |

`virtual_type` identifies recognized virtual-machine vendors without replacing
Munki's built-in `machine_type` condition. It is an empty string on physical
Macs and `unknown` when a virtual machine's vendor cannot be determined.
`physical_or_virtual` retains its simpler two-value domain.

`system_extensions` reads Apple's system-extension database and includes only
records in the `activated_enabled` state. The `approved_system_extension_*`
keys expose approved policy identifiers from the same database, grouped by
bundle ID, team ID, and combined `TEAMID:bundle.id` keys.

`shard` is derived from the hardware serial number, falling back to the
platform UUID and then to `99`. It is calculated as `MD5(identifier) % 100 + 1`
so it is stable across reinstalls without relying on a site-specific persisted
data source.

Each `*_upgrade_supported` perl is omitted entirely, rather than reported
`false`, once a Mac is already at or past that release: being there already
is not an upgrade path, and seventeen redundant `false` values are not
useful information either. Falling below a release's minimum source version
is still reported as explicit `false`, since that is worth knowing.
`latest_macos_supported` and `highest_supported_macos_version` are the two
exceptions to the omit-when-obvious rule: they are always present, evaluate
hardware capability only, and ignore both the current OS version and any RAM
minimum, so a Mac already past every per-release target still gets a
straight answer instead of a blank stare.

The included collection stays focused on broadly useful inventory and
compatibility answers. Site-specific and community additions can be dropped
in without changing the runner or a registration manifest.

## Installation

Download the current package from
[GitHub Releases](https://github.com/weswhet/munki-perls/releases/latest), then
install it at the system volume:

```sh
sudo /usr/sbin/installer -pkg munki-perls-0.1.N.pkg -target /
```

The package installs one executable runner, its shared modules, and the bundled
non-executable plugins at `/usr/local/munki/conditions`.

To install directly from a checkout, preserve modes while copying the layout:

```sh
sudo /bin/mkdir -p /usr/local/munki/conditions
sudo /usr/bin/ditto conditions /usr/local/munki/conditions
```

Munki executes `munki_perls.pl` and ignores the `perls` directory. The runner
loads every valid plugin and writes their combined output to the configured
`ManagedInstallDir/ConditionalItems.plist` once.

## Using the conditions

The runner accepts `--output PATH`, `--only NAME`, `--verbose`, and `--help`.
Use `--only` with an output override to test one plugin without involving the
production plist:

```sh
/usr/local/munki/conditions/munki_perls.pl \
  --only virtual_type \
  --output /tmp/ConditionalItems.plist \
  --verbose
```

Set `MUNKI_PERLS_DEBUG=1` for the same concise diagnostics as `--verbose`.
Runner diagnostics identify the plugin and failure stage without printing its
returned values. Plugin authors should likewise keep sensitive values out of
exceptions. Missing commands on older systems yield the established `Unknown`
or `NONE` fallback and allow the remaining plugins to continue with their day.

### Selecting plugins

Managed preferences in the persistent `org.munki.perls` domain can prevent
unneeded plugins from being loaded or run. The domain accepts two optional
array-of-string keys. The same keys may instead be placed in the fixed local
file `/usr/local/munki/conditions/perls/config.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>included_perls</key>
<array>
    <string>console_user</string>
    <string>virtual_type.pl</string>
</array>
</dict>
</plist>
```

- When `included_perls` is present, only its valid, installed entries run and
  `excluded_perls` is ignored completely. A present but empty include array
  runs no plugins.
- When only `excluded_perls` is present, all plugins except its valid,
  installed entries run. A present but empty exclude array runs all plugins.
- With neither key present, all plugins run.

Entries are case-sensitive plugin filename stems; the `.pl` suffix is
optional. Selection applies to the plugin file, so a custom plugin returning
several keys is included or excluded as one unit. Duplicate entries have no
additional effect.

Selection sources are resolved in this order: `--only`, managed preferences
when either recognized key exists, then `perls/config.plist`, then all plugins.
`--only` bypasses both configuration sources. A readable preference domain
without either key allows the local file to be used; unrelated plist keys are
ignored. Existing managed-preference deployments therefore remain
authoritative without migration.

The runner skips and diagnoses invalid containers, non-string, empty, or
unsafe entries, and names that do not match an installed plugin. It does not
echo unsafe values or any values returned by plugins. The selected mode remains
authoritative: for example, an invalid `included_perls` value does not make the
runner fall back to loading every plugin. If preferences cannot be read, the
local file is tried. A missing or keyless local file is no configuration and
runs all plugins. An unsafe, unreadable, malformed, or non-dictionary file is
diagnosed and ignored. XML and binary property lists are accepted through
Foundation. With `--verbose` or `MUNKI_PERLS_DEBUG=1`, diagnostics identify the
active source and report the mode and matched/skipped plugin counts.

The local file must be a regular file, not a symlink, owned by the same account
that runs the condition (normally `root`), and not writable by group or others.
Deploy it without relying on the package, which deliberately does not ship or
overwrite one:

```sh
sudo /usr/bin/install -o root -g wheel -m 0644 config.plist \
  /usr/local/munki/conditions/perls/config.plist
```

## Adding a plugin

A plugin is an ordinary, non-executable Perl file with a `perls()` function.
It may return one key or a related group of keys:

```perl
use 5.008006;
use strict;
use warnings;
use MunkiPerls qw(
    perl_array perl_bool perl_dictionary perl_integer perl_real perl_string
);

sub perls {
    return {
        office_name => perl_string('West'),
        office_floor => perl_integer(4),
        office_features => perl_array('studio', 'kitchen'),
        office_details => perl_dictionary(
            open => perl_bool(1),
            capacity_ratio => perl_real('0.75'),
        ),
    };
}

1;
```

Install it as trusted root code. The runner rejects symlinks, files with the
wrong owner, and files or directories writable by group or others:

```sh
sudo /usr/bin/install -o root -g wheel -m 0644 \
  office.pl /usr/local/munki/conditions/perls/office.pl
```

Plugins are loaded in sorted filename order and isolated namespaces. A broken
plugin is diagnosed and skipped without losing valid results from the others.
When plugins return the same key, the later filename wins; verbose mode reports
the replacement. Prefix an intentional site override accordingly, for example
`zz_site_virtual_type.pl`.

Values use explicit constructors so plist booleans and numbers do not become
ambiguous Perl scalars. Arrays and dictionaries may be nested recursively;
bare scalar members are treated as strings.

## Upgrade compatibility

One plugin, `upgrade_supported.pl`, emits one boolean perl per eligible
release, evaluated against a single allow-list schema shared by all
seventeen. Every release declares an `allow` list of conditions (a `model`,
a `hardware_target`, or a `cpu` family and minimum clock speed, optionally
combined with `all` for AND semantics), and a Mac is eligible if it matches
at least one of them. All seventeen share one reboot-scoped hardware
snapshot and evaluate their named result in the same order:

1. A Mac already at or above the target omits that release's perl instead of
   reporting `false`.
2. A Mac below the release's minimum source version is not eligible.
3. An eligible virtual machine is supported, regardless of any RAM minimum.
4. A physical Mac must clear the release's RAM minimum, if it declares one,
   then match one of its allowed conditions.

| Perl | Target | Eligible source versions |
| --- | ---: | --- |
| `leopard_upgrade_supported` | 10.5 | no declared minimum, any earlier release |
| `snowleopard_upgrade_supported` | 10.6 | 10.5.8 through the release below 10.6 |
| `lion_upgrade_supported` | 10.7 | 10.6.8 through the release below 10.7 |
| `mountainlion_upgrade_supported` | 10.8 | 10.6.6 through the release below 10.8 |
| `mavericks_upgrade_supported` | 10.9 | 10.6.6 through the release below 10.9 |
| `yosemite_upgrade_supported` | 10.10 | 10.6.6 through the release below 10.10 |
| `elcapitan_upgrade_supported` | 10.11 | 10.6.8 through the release below 10.11 |
| `sierra_upgrade_supported` | 10.12 | 10.7.5 through the release below 10.12 |
| `mojave_upgrade_supported` | 10.14 | 10.8 through the release below 10.14 |
| `catalina_upgrade_supported` | 10.15 | 10.9 through the release below 10.15 |
| `bigsur_upgrade_supported` | 11 | 10.7 through the release below 11 |
| `monterey_upgrade_supported` | 12 | 10.7 through the release below 12 |
| `ventura_upgrade_supported` | 13 | 10.7 through the release below 13 |
| `sonoma_upgrade_supported` | 14 | 10.7 through the release below 14 |
| `sequoia_upgrade_supported` | 15 | 10.7 through the release below 15 |
| `tahoe_upgrade_supported` | 26 | 10.7 through the release below 26 |
| `goldengate_upgrade_supported` | 27 | 10.7 through the release below 27 |

Mountain Lion, Mavericks, Yosemite, and El Capitan additionally require 2GB
of RAM on physical hardware; that minimum is ignored for virtual machines.

Leopard, Snow Leopard, and Lion predate Apple's board-id compatibility check
entirely, so their eligibility comes from CPU family and clock speed instead
of a model or board table: Leopard needs PowerPC G4 at 867MHz or faster, any
G5, or any Intel Mac; Snow Leopard needs any Intel Mac; Lion needs a
64-bit-capable Intel Mac, which rules out the original 32-bit-only Core Duo
and Core Solo machines.

Sierra uses the final model and board tables from the parent of
[`munki-facts` removal commit `bbeee28dd2a5`](https://github.com/munki/munki-facts/commit/bbeee28dd2a5).
Mojave, Catalina, Big Sur, and later continue the lineage at
[`a22a02a0304a`](https://github.com/munki/munki-facts/commit/a22a02a0304a). Mountain
Lion, Mavericks, Yosemite, and El Capitan predate that lineage's board-id
records, so their model lists were instead translated from
[`hjuutilainen/adminscripts`](https://github.com/hjuutilainen/adminscripts)'
real board-id compatibility checks via
[`littlebyteorg/appledb`](https://github.com/littlebyteorg/appledb)'s device
database, which maps board ids to Model Identifiers. This repository no
longer stores or reports a Mac's board id itself; only the release tables
above needed it, once, at data-entry time.

## How it stays boring

- Property lists are read, constructed, typed, and serialized with Foundation.
- Booleans and numbers retain native plist types; arrays and dictionaries may
  contain recursively typed values.
- Plugins are discovered deterministically, validated independently, and
  collected before writing.
- A stable sidecar lock serializes updates with other Munki conditions.
- Foundation atomically replaces the destination, so a partial file does not
  become tomorrow's inventory puzzle.
- Upgrade and virtualization conditions share a hardware-only snapshot at
  `<output>.munki-perls-hardware-cache.plist`. Its schema and `kern.boottime`
  identifier keep it valid only for the current boot. A malformed or stale
  cache—or any lock or write failure—falls back to live collection and never
  prevents a perl from being written.
- Bundled subprocesses use allowlisted absolute paths and direct argument
  vectors. The shell is not invited; it tends to bring interpretation with it.
- Virtual hardware is detected from the shared snapshot. Only the
  `virtual_type.pl` plugin makes the vendor-specific `system_profiler` query,
  and only for virtual Macs, to distinguish VMware, VirtualBox, Parallels, and
  the entirely respectable `unknown`.
- Hardware identity comes from `system_profiler` model lookups and, for the
  CPU-gated releases, family and clock speed pulled from `sysctl`. Nothing
  shells out to `ioreg -a` anymore, which is convenient, because it never
  worked on Tiger's `ioreg` in the first place.

Back to My Mac is queried through `scutil` only on Mojave and older and is
always false on Catalina and newer, which settled that question rather neatly.

## Maintainer tools

The project website lives in `site/` and builds to the ignored `dist/`
directory. It uses a pinned Tailwind toolchain and project-relative asset URLs:

```sh
npm ci
npm run dev       # local server with CSS watching
npm run build     # production output
npm run check     # output, URL, and ES5 fallback checks
npm run preview   # serve the production output
```

`tools/extract_supported_devices.pl` reads an installer asset plist with
Foundation, validates and deduplicates `SupportedDeviceModels`, and prints a
sorted Perl `qw(...)` table.

`tools/build-pkg.pl` stages the payload with native Perl file APIs and hands
it to `/usr/bin/pkgbuild`. The tool is Perl 5.8.6-compatible, but packages
must be built on a newer host that provides `pkgbuild`; Tiger and Leopard are
supported installation targets, not package build hosts, and asking a G5 to
run `pkgbuild` would be a poor use of everyone's afternoon. By default it
creates an unsigned package with identifier `com.github.weswhet.munki-perls`,
installed at `/usr/local/munki/conditions`:

```sh
tools/build-pkg.pl --verbose
tools/build-pkg.pl --version 0.1.42 --output /tmp/munki-perls-0.1.42.pkg
tools/build-pkg.pl --version 0.1.42 \
  --sign "Developer ID Installer: Wesley Whetstone (2D8XQ77EBQ)" \
  --output /tmp/munki-perls-0.1.42.pkg
```

If `zopfli` is on `PATH`, the built package's payload gets a second pass:
unpacked, recompressed with zopfli's considerably more stubborn DEFLATE
search, verified byte-for-byte against the original before it's trusted, and
repacked. The output is still perfectly ordinary gzip, so nothing downstream
needs to know or care, it just arrives a few hundred bytes lighter. This
project has diligently reduced how many system commands it shells out to,
consolidated how many times it asks `system_profiler` the same question, and
now also squeezes the installer a little harder than strictly necessary.
Every byte counts. When `zopfli` isn't installed, the build proceeds exactly
as before; this is a bonus, not a requirement.

Setting `MUNKI_PERLS_ZOPFLI=/path/to/zopfli` pins the exact binary to use and
skips the `PATH` search entirely, including the fallback: an empty or
nonexistent path means "not available," not "go look around for something
else with the same name." CI sets this to the binary it just downloaded,
checksummed, and built for itself, rather than trusting whatever else might
already be sitting on the runner's `PATH`. Everyday local use doesn't need
it; a `zopfli` on `PATH` is picked up automatically.

After all three Perl-version jobs pass, every push to `main` uses the
workflow run number to build version `0.1.N`, creates tag `v0.1.N`, and
publishes the package on a GitHub Release. Re-running the workflow replaces
the existing asset rather than attempting to improve arithmetic.

## Testing

Run the syntax and test suites with Apple's Perl:

```sh
find conditions tools t -type f \
  \( -name '*.pl' -o -name '*.pm' -o -name '*.t' \) \
  -exec /usr/bin/perl -Iconditions/lib -c {} \;
/usr/bin/prove -lr t
```

CI runs three Perl versions in parallel, one job per version, across every
standard GitHub-hosted macOS image: ARM on `macos-14`, `macos-15`, and
`macos-26`, plus Intel on `macos-15-intel` and `macos-26-intel`.
`perl-latest` uses each image's own system Perl, currently 5.34.1. `perl-5-8-6`
and `perl-5-8-8` each install a checksum-pinned build of the exact Perl that
Tiger and Leopard shipped, respectively, since no GitHub-hosted image is old
enough to have either lying around.

Injected OS, hardware, and Foundation plist fixtures exercise earlier macOS
and virtual-machine branches on `perl-latest`, which also builds and expands
a package, inspects its BOM, and verifies the complete native plist contract.
Package tests skip on hosts without `/usr/bin/pkgbuild`. The two historical
Perl jobs compile every Perl source and test against a compile-only
Foundation stub, then run the Foundation-independent syntax, policy, and
package tests, since neither Tiger nor Leopard's real `Foundation` bridge is
available on a GitHub-hosted runner.

The genuine article has already run once: a real PowerPC G5, tested directly
rather than through any of the above, running the actual conditions runner
end to end and correctly reporting `leopard_upgrade_supported=true` for its
trouble. What CI cannot yet do is install an actual `.pkg` on real or virtual
Leopard hardware, verify the native plist types and hardware-cache reuse
there, and run the Foundation-dependent tests against the genuine bridge.
Continue smoke-testing new releases as before. A successful run is expected
to be thoroughly boring. Here, that is a feature.

## Lineage and license

Licensed under the [Apache License 2.0](LICENSE.md). Hardware compatibility
tables and original perl behavior follow the `munki-facts` lineage described
above.
