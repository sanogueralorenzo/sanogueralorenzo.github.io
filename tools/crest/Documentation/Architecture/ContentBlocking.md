# Content blocking

Crest's Balanced protection bundles Peter Lowe’s Ad and tracking server list
and EasyList cosmetic filters, sources also used by uBlock Origin. WebKit
compiles them into one native content rule list. Each Space has one on/off
setting for both request blocking and cosmetic filtering.

## Built-in protection

The core blocks third-party network loads from listed hosts and their
subdomains, while allowing top-level documents. EasyList's native CSS selectors
hide advertising containers, including dynamically added elements, so they no
longer reserve layout space. Site scopes and cosmetic exceptions are translated
by AdGuard's SafariConverterLib, rather than site-specific Crest heuristics.
Cosmetic exceptions precede host rules and cannot bypass network protection.

Balanced also blocks third-party requests to `fundingchoicesmessages.google.com`,
matching uBlock Origin's generic ad-block recovery rule. This prevents that
service from showing its recovery wall when cosmetic filtering hides detection
bait. The rule applies across sites and ships as a compatibility supplement to
the host list.

The compiled-list identifier hashes the complete rule source, so either data
update invalidates the cache. No lists or executable filtering code are
downloaded during browsing. The installed app uses WebKit's default rule store.
A named isolated profile uses `ContentRules` beside its session; anonymous
isolated launches use a temporary store removed with its provider. Isolation
never disables blocking. Compilation and query failures propagate to the
blocking controller.

## Updating bundled data

Refresh hosts with `python3 Scripts/update-content-blocking-hosts.py`. The updater
retains the generic compatibility supplement, including when upstream adds one
of its hosts.
For cosmetics, build the offline converter from SafariConverterLib v4.3.1:

```sh
git clone --depth 1 --branch v4.3.1 https://github.com/AdguardTeam/SafariConverterLib.git /tmp/SafariConverterLib
swift build -c release --package-path /tmp/SafariConverterLib --product ConverterTool
python3 Scripts/update-content-blocking-cosmetics.py --converter /tmp/SafariConverterLib/.build/release/ConverterTool
```

Then run `Scripts/control-plane/generate-contracts.sh` and the native content
blocking tests. Updates ship with app releases. Attribution and licenses are
preserved in the dependency catalog, `PeterLowe-LICENSE.txt` (noncommercial)
and `EasyList-LICENSE.txt` (CC-BY-SA 3.0) in `CrestShared/Resources`.

## Scope and compatibility

This is native host and cosmetic filtering, not the full uBlock engine. It does
not run scriptlets, procedural filters, or network resource-collapse scripts,
and does not interpret EasyList's network rules. Unsupported advanced cosmetic
filters are omitted by the converter. Some sites may still reserve whitespace.

The built-in list uses WebKit's content-rule API and has no effect on Chromium,
which declares content blocking unavailable and relies on extensions.

Blocking can break a site. Page and command menus can turn protection off for
the current Space. Removing Crest's rule list preserves rules installed by
other clients of the user content controller.
