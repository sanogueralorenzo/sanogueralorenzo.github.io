# Content blocking

Crest's Balanced protection is one bundled ruleset that WebKit applies through
its native content-rule-list API. Each Space turns it on or off independently.

## Built-in protection

The bundled rules block a deliberately small set of well-known third-party ad
and analytics hosts. They give a privacy baseline without downloading remote
rule sources, parsing third-party filter syntax, or placing another project's
converter inside Crest's trusted update path.

The portable core owns the rules. `ContentBlockingPolicy.Balanced` in
`CrestCore` carries the blocked host suffixes and a versioned identifier, and
the `BalancedProtectionRules` query returns them as a `ContentRuleList`: that
identifier with the WebKit content-rule source. WebKit's binding compiles the
source once, caches the resulting `WKContentRuleList` under the identifier, and
builds each page in a Space where Balanced protection is on with it. If the core cannot answer, nothing
is compiled. Turning protection on or off reloads the visible pages so the
change takes effect without touching another Space.

## Extensions provide broader blocking

Crest does not ship a downloadable filter-list catalog or accept custom
Adblock-style list URLs. People who want broader coverage, cosmetic filtering,
regional lists or project-specific rules can install a content-blocking
extension. Extensions keep their own source, update and licensing decisions,
so Crest never redistributes or converts those lists.

The split is intentional:

- Crest owns a small first-party baseline that can be reviewed.
- Extensions own advanced blocking and the list ecosystems people choose.
- A failed extension cannot change Crest's bundled rules or another Space's
  extension state.

## Chromium

Crest's built-in protection is a WebKit content-rule list, so it has no effect
on Chromium. Chromium's own subresource filter depends on Safe Browsing list
distribution that Crest does not run, and Crest does not convert its rules into
a second format for one engine. The Chromium registration therefore declares
`content-blocking` unavailable. The Privacy settings section shows no Balanced
control and says instead that blocking comes from the extensions the person
installs, and the page menu item is not installed. Blocking on Chromium comes
from an extension such as uBlock Origin Lite.

## Compatibility

Balanced protection can occasionally break a site because it blocks known
third-party hosts. On WebKit, the page and command menus let the person turn
content blocking off for the current Space. An extension may add its own site
controls.
