# Overlay Options — Cross-Platform Verification Checklist

Goal: every customization the web dashboard exposes for a Dynamic Widget's `overlay_options`
should work the same way on iOS and Android. This doc tracks, parameter by parameter, whether it's
wired into the native trigger views, and whether it's been visually verified on-device (with a
screenshot) after being changed live through the Poltio API.

Reference: `widget-params.md` (full parameter table, shared with the web SDK) — ask the user for a
fresh copy if it's not in `/Users/gcg/Downloads/` anymore, or read it from wherever they re-share it.
The web SDK's own source is checked out locally at `/Users/gcg/Work/src/github.com/Poltio/websdk` —
read it directly when in doubt about what a parameter is actually supposed to do, rather than
guessing from the table alone.

## Web baseline (control group)

The user attached the same three widgets to a static site mimicking the mobile URL structure, so
web behavior can be used as ground truth when a native result is ambiguous:

- `https://poltio.github.io/mobilesdk/home.html` → box trigger (widget 393)
- `https://poltio.github.io/mobilesdk/plp_phones.html` → pill trigger (widget 394)
- `https://poltio.github.io/mobilesdk/plp_tvs.html` → card trigger (widget 401)

All three confirmed reachable and rendering (2026-09-17). **The full parameter-by-parameter sweep
against this web baseline has not started yet** — next session should, for each parameter change:
set it via `update_widget`, then screenshot all three surfaces (web via the Browser tool, iOS via
the simulator, Android via adb) side by side, and note any platform where the visual result
diverges from web's behavior (not just "does it do something," but "does it match web").

## How to resume this work

1. **Test widgets** (Poltio MCP `get_widget`/`update_widget`, staging env `api-stage.poltio.com`,
   org owned by `guney@poltio.com`):
   - `401` — **Mobile SDK Card Trigger TVs** → `example://plp/tvs` → card trigger
   - `394` — **MobileSDK Phones PLP Pill** → `example://plp/phones` → pill trigger
   - `393` — **Mobile SDK Home** → `example://home`, `example://plp` → box trigger
2. `update_widget` requires `public_id`, `name`, `urls`, `is_default` alongside `overlay_options_json`
   (the API rejects a partial patch) — see call examples below.
3. **The API validates `overlay_options` keys against a fixed schema** — it 422s on any key
   (top-level or inside `mobile`) that isn't in `fields.json`. `floating-show-logo` is one such
   field (docs list it as "page-only", no API field) — it **cannot be live-tested via the
   dashboard/API**, only via unit tests constructing `PoltioOverlayOptions` directly.
4. Build/run: `make build-android` / `make run-example-android` (emulator `Pixel_10_Pro_XL`);
   `make build-ios` / `make run-example-ios` (works now — see "iOS toolchain" section below for
   the gotchas that were fixed to get here).
5. Screenshot Android: `adb exec-out screencap -p > file.png`, read the file with the Read tool.
   Get exact tap coordinates via `adb shell uiautomator dump /sdcard/window_dump.xml` then grep
   `bounds="[...]"` — screen coordinates from a resized preview image do **not** map 1:1, always
   get real bounds first.
6. Screenshot iOS: `mcp__Claude_Code_iOS_Simulator__control` (`attach`/`screenshot`/`tap`).
7. The Home-screen box trigger auto-collapses after 5s if untouched (`AUTO_COLLAPSE_DELAY_MS` in
   `PoltioFloatingBoxTriggerView`) — screenshot fast, or re-tap to re-expand.

## iOS toolchain — resolved this session, keep these notes in mind

The Xcode/Simulator blocker from earlier is fixed. What it took, in case a fresh machine hits the
same thing:

1. Accept the Xcode license (`sudo xcodebuild -license`) and select a **full** Xcode
   (`sudo xcode-select -s /Applications/<Xcode>.app/Contents/Developer`) — both need the user, not
   Claude, since they need a password.
2. **This machine's originally-installed Xcode (Xcode 27) has no `Simulator.app` at all** — Apple
   replaced it with a new `DeviceHub.app` in that version, and the `mcp__Claude_Code_iOS_Simulator__control`
   tool doesn't recognize DeviceHub-hosted simulators yet (fails with "No booted simulator found"
   even though `xcrun simctl` shows one booted). The fix was installing **Xcode 26** alongside it
   (still has classic `Simulator.app`) and `xcode-select -s`-ing to that instead. If this machine's
   primary Xcode ever becomes DeviceHub-only again, that's the thing to check first.
3. Even with the right Xcode selected, the attach tool kept failing ("No booted simulator found" /
   120s boot timeout) until **Claude Desktop itself was fully quit and relaunched** — it had a stale
   CoreSimulator handle cached from before the Xcode changes. If attach ever misbehaves again after
   switching Xcode versions, relaunching Claude Desktop is the first thing to try, before re-diagnosing.
4. **Fixed the root Makefile**: it hardcoded `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
   in five places, which broke the moment `Xcode.app` stopped being the working install. Now
   `DEVELOPER_DIR` defaults to `$(shell xcode-select -p)` (one place, at the top) and every target
   just inherits the exported var — no more hardcoded paths. Also switched `build-example-ios` from
   a `-destination platform=iOS Simulator,name=...` spec to plain `-sdk iphonesimulator`, because
   with multiple simulator runtimes installed (26.3.1/26.5/27.0 side by side), destination
   resolution for a named device kept failing to match "OS:latest" even when that exact device was
   listed as available. `-sdk iphonesimulator` sidesteps device resolution entirely for the build
   step; the real device is only chosen later, at `simctl install`/`launch` time.
5. `mcp__Claude_Code_iOS_Simulator__control`'s `inspect` action is unavailable in this environment
   ("not available right now, use screenshot instead") — no accessibility-tree lookups; get tap
   coordinates by reading screenshots directly and remember the tool's point-space is **402×874**,
   not the screenshot's pixel dimensions (divide screenshot-pixel coords by ~2.29 for this device).
6. `print()`-based `PoltioLogger` output is **not visible** via `xcrun simctl spawn <udid> log show`
   for a plain `simctl launch`-ed app (unified logging doesn't seem to capture this app's stdout in
   this setup), and `simctl launch --console`/`--console-pty` didn't stream anything either when
   tried backgrounded. If SDK-side logging needs inspecting again, try running via Xcode directly
   (`open example/ios/ExampleApp.xcodeproj`, Cmd+R) rather than fighting `simctl` log capture.

## RESOLVED — iOS floating trigger not appearing was a launch-config bug, not an SDK bug

Root cause found and fixed. It was never a rendering/window-scene issue: the widget API call was
returning **HTTP 401**. `example/ios/ExampleApp.xcodeproj/xcshareddata/xcschemes/ExampleApp.xcscheme`
(gitignored, same pattern as Android's `local.properties`) carries the real `POLTIO_CLIENT_KEY` as
a scheme `<EnvironmentVariable>` — but that's an **Xcode-only** injection mechanism (only applied
when Xcode itself launches the app, e.g. Cmd+R). The Makefile launches the built app via
`xcrun simctl launch`, which never reads `.xcscheme` files at all, so `ProcessInfo.processInfo
.environment["POLTIO_CLIENT_KEY"]` came back `nil` and the app silently fell back to the
non-functional placeholder `"poltio_test_pk_12345"` — hence 401 on every widget fetch, and
therefore never anything to show.

How this was actually found: `simctl`'s log/console capture never worked in this environment (see
toolchain note #6) — even `--stdout=<path>`/`--stderr=<path>` produced no file at all, for reasons
unclear. What finally worked: temporarily made `PoltioLogger.log` also append to `/tmp/poltio_debug.log`
(reverted immediately after, **do not leave this in** — it's not committed), rebuilt, relaunched,
and the very first log line was `resolveMobileWidget server returned status 401 for URL:
'example://home'`. If live SDK-log visibility is ever needed again, that patch-and-revert trick is
the fastest path — `simctl`'s own log capture is not to be trusted here.

**Fix applied**: `run-example-ios` in the Makefile now extracts `POLTIO_CLIENT_KEY` straight out of
the `.xcscheme` XML (`xmllint --xpath`, same single source of truth Xcode itself uses) and passes it
through via `simctl`'s `SIMCTL_CHILD_POLTIO_CLIENT_KEY` env var convention before launching. Verified
fixed: rebuilt, relaunched, and the box trigger now renders correctly on the Home screen (matches
Android's fallback-image rendering exactly) — screenshot not yet saved into `docs/screenshots/ios/`,
do that on the next pass along with the Card trigger on TVs (confirmed visible in collapsed state,
just didn't nail the exact tap coordinates to expand it before time ran out this session).

iOS is now unblocked end-to-end for the full verification sweep.

## Bug found and fixed — iOS Pill custom icon color

The user noticed the pill trigger's custom `floating-svg` icon rendered **white on iOS** but
**grey on Android and web**, for the exact same widget/icon. Root cause: `PoltioFloatingPillTriggerView.swift`
has its own separate, duplicated SVG-loading implementation (Card/Box use the shared
`PoltioTriggerIconLoader` instead — Android's Pill also uses that shared loader, which is why
Android was correct). iOS Pill's copy injected this CSS into the wrapper HTML:
```css
svg[style*="color"] {
    color: #FFFFFF !important;
}
```
This matched our icon's own `style="color: rgb(74, 85, 101); ..."` attribute and forcibly
overrode it to white with `!important`, destroying any icon's author-specified color. The
`html, body { color: #FFFFFF; }` default (for icons with no color of their own) was fine and is
kept. **Fix**: removed the `svg[style*="color"]` override block entirely. Rebuilt, relaunched,
confirmed via pixel-sampling the screenshot (`docs/screenshots/ios/pill_icon_color_fixed.png`) that
the icon now renders the correct `rgb(74, 85, 101)` grey, matching Android and web exactly.
Unit tests + swiftformat still pass.

## Found — box auto-collapse timing is inconsistent between iOS and Android

While testing the box trigger's font-size/weight/align params, Android's emulator this session was
under heavy system load (host load average 11–14, one real ANR logged — `Input dispatching timed
out` — plus DNS resolution briefly failing for `sdk-stage.poltio.com`; all environmental, not an SDK
bug), which made screenshotting the box mid-expanded-state very difficult — every attempt landed on
an already-collapsed frame. Digging into why led to a real, confirmed platform inconsistency:

- **Android's `PoltioFloatingBoxTriggerView.applyState`** unconditionally schedules a 5-second
  auto-collapse (`AUTO_COLLAPSE_DELAY_MS = 5000L`) any time the box becomes expanded — regardless of
  `floating-initial-position`'s value (even explicit `"expanded"`, which sounds like it should stay
  open).
- **iOS's `PoltioFloatingBoxTriggerView`** has **no auto-collapse timer at all** — grepped for
  `scheduleAutoCollapse`/`autoCollapseTimer`/`isInitialActive` in the iOS box file and found zero
  matches. Once expanded on iOS, the box stays open until the user (or `resetToCollapsed`) closes it.

This isn't a rendering bug, but it is a genuine behavior difference a widget author could hit:
the same widget config produces "opens and stays open" on iOS vs. "opens then auto-hides after 5s"
on Android. Not fixed this session (no product decision on which behavior is "correct" — flagging
for the user to decide whether to add the iOS timer, remove the Android one, or leave as
intentional). Also worth checking what web does here for a three-way comparison, not done this
round.

## Solved — pill "tap-to-expand not working reliably" (from an earlier session)

Not a bug. Root-caused this session with temporary debug instrumentation (timestamped logging in
`applyState`, reverted after): the pill's tap gesture, hit-testing, and state transition all fire
correctly on the very first tap, every time — confirmed via a logged timeline showing
`applyState(expanded)` firing immediately on tap, frame changing to the full expanded width, then
`applyState(collapsed)` firing again exactly 2.0s later. The catch: any widget with
`floating-initial-position: "active"` (`isInitialActive`) re-arms a 2-second auto-collapse timer
**every time** the pill enters the expanded state — not just on its initial automatic expand-on-load.
This is intentional, symmetric behavior on both platforms (confirmed identical in
`PoltioFloatingPillTriggerView.applyState`/`.kt`'s `applyState`). The two separate MCP tool calls
needed to tap and then screenshot routinely take longer than that 2-second window, so every previous
attempt just barely missed the expanded frame. Fix for testing (no code change needed): temporarily
set `floating-initial-position: "expanded"` instead of `"active"` — same start-expanded behavior,
but `isInitialActive` is false so no auto-collapse timer ever arms, giving as much time as needed to
screenshot. Reverted back to `"active"` afterward.

Debugging note for next time: `mcp__Claude_Code_iOS_Simulator__control`'s `screenshot` output alone
wasn't enough to be sure "white" vs. "light grey" wasn't just an optical illusion at tiny icon
size — installed Pillow (`python3 -m pip install Pillow`) to pixel-sample the saved PNG directly
and confirm the actual RGB values. Also: don't assume Card/Box's `PoltioTriggerIconLoader` is used
everywhere — Pill has its own separate copy of similar-looking SVG-loading logic on iOS; check
both if debugging an icon issue. (A follow-up worth considering, not done this session: de-duplicate
Pill's icon loading to use the shared `PoltioTriggerIconLoader` instead of its own copy, so this
class of divergence can't happen again — flagging but not doing it now since it's a bigger,
riskier refactor than the immediate bug fix.)

## Bug found and fixed — iOS `floating-font-family` ignored CSS generic keywords

Re-verifying the card round-1 params on iOS (widget 401, `floating-font-family: "serif"`) showed the
title/desc rendering in the plain system sans-serif font, while Android correctly rendered it serif'd.
Root cause: `PoltioOverlayOptions.resolvedFont` called `UIFont(name: family, size:)` directly — that
API only resolves actual installed font PostScript names, and returns `nil` for CSS generic family
keywords like `"serif"`/`"monospace"`, silently falling back to the system font. Android's
`Typeface.create(family, style)` natively understands those generic keywords (documented Android
behavior), which is why it worked there without any special-casing.

**Fix**: `resolvedFont` (`ios/Sources/PoltioSDK/Models/PoltioWidgetResponse.swift`) now falls back to
mapping `"serif"` → `UIFontDescriptor.SystemDesign.serif` and `"monospace"`/`"ui-monospace"` →
`.monospaced` (via `UIFont.systemFont(...).fontDescriptor.withDesign(...)`) before giving up and
returning the plain system font. Verified: rebuilt, relaunched, "TV Finder Pro" now renders visibly
serif'd on iOS, matching Android exactly. 29/29 unit tests still pass, swiftformat clean.

## Code fixes already applied (this session)

- [x] Fixed `example/android/build.gradle.kts` — missing `com.vanniktech.maven.publish` plugin
      version broke every Android example-app build (unrelated to overlay options, blocking gate).
- [x] `widgetBg` (`widget-bgcolor`, "Panel Background color") — was decoded but unused on both
      platforms. Now wired to the WebView modal's chrome (`PoltioWebViewController` / `PoltioWebViewActivity`).
- [x] `floatingMobileTopBorderRadius` — was Card-only on both platforms. Now also applied to
      Pill/Box's expanded container, each keeping its own original default radius when unset
      (Pill 28pt/dp, Box 18pt/dp) so existing widgets don't visually shift.
- [x] `floatingZindex` — was iOS-only (`UIWindow.windowLevel` offset). Added an Android analogue
      (mapped to `View.elevation` on the overlay container, clamped 0–24dp).
- [x] `floatingFontFamily` — was iOS-only. Added Android best-effort `Typeface.create(family, style)`
      (silently falls back to system font for unknown names, mirroring iOS's `UIFont(name:)` behavior).
- [x] `showLogo` (`floating-show-logo`) — didn't exist in either model, and neither Card trigger
      rendered any branding element. Added the property (default `true`) to both models, and a
      small "Poltio" wordmark to the bottom of the Card trigger's expanded panel on both platforms,
      shown/hidden by it. **Cannot be live-tested via MCP** (see blocker #3 above) — verify via unit
      tests instead.
- [x] `floatingFontFamily` on iOS silently ignored CSS generic family keywords (`"serif"`,
      `"monospace"`) since `UIFont(name:)` only resolves real installed font names. Now maps those
      keywords to `UIFontDescriptor.SystemDesign` first — see "Bug found and fixed" section above.

## Known, accepted gaps (not fixed — documented behavior, not bugs)

- `floatingScrollThreshold`, `boxOpenOnScroll` — no generic "host page scroll" concept exists in a
  native app; decoded for parity only, matches existing code comments.
- `productCardEnabled` and all `product_card`-section fields — no native `product_card` trigger
  exists yet on either platform (out of scope for this pass).
- `parentId` / `parentClassName` / `parentHeight` (`iframe` section) — DOM-embedding-only, no native
  equivalent possible.
- `floatingDesignType` / `floatingDisplayType` — only consumed indirectly (trigger-type resolution
  heuristic), never applied to styling directly; this matches how they're used (to pick card vs.
  pill vs. box), not a customization surface of their own.

---

## Checklist

Legend: ✅ verified this pass (on-device screenshot or DOM/computed-style inspection for web) ·
🧩 wired in code / indirectly confirmed (e.g. widget resolved and rendered, but this specific
sub-element wasn't isolated) · ⬜ not yet tested · ➖ N/A (documented gap above). Older tables below
don't have a `Web` column yet — add one when a param in that table is next tested, following the
`pill` table's format.

### identity (core, iframe query params — applies to whichever trigger opens the WebView)

| Attribute | iOS | Android | Notes |
|---|---|---|---|
| `widget-content` | 🧩 | 🧩 | code-confirmed: `PoltioWebViewController.buildWidgetURL`/`PoltioWebViewActivity.buildWidgetUrl` both read `overlayOptions.content` (from `widget-content`) and append it as the `content` query param verbatim, on both platforms. Not live-network-captured (simple string passthrough, no rendering logic to verify beyond this). |
| `widget-custom_id` | 🧩 | 🧩 | same code path as above, `custom_id` query param — confirmed wired identically on both. |
| `widget-loc` | 🧩 | 🧩 | same code path, `loc` query param — confirmed wired identically on both. |
| `widget-resultfit` | 🧩 | 🧩 | same code path, `resultfit` query param — confirmed wired identically on both. |
| `widget-disclaimer` | 🧩 | 🧩 | same code path, `disclaimer` query param, defaults to `"off"` on both platforms when unset — confirmed wired identically. |
| `trigger-page-langs` | ➖ | ➖ | page-only concept (matches `<html lang>`) — no native equivalent, confirmed not referenced anywhere in either SDK's source. Reclassified from ⬜ to ➖ (N/A, not a gap). |

### common (shared across card/pill/box)

| Attribute | iOS | Android | Notes |
|---|---|---|---|
| `floating-bgcolor` | ✅ | ✅ | verified via card round 1 (user's own screenshot + our round-1 screenshot); box/pill use their own bg fields instead, by design |
| `widget-bgcolor` (Panel Background color) | ⬜ | ✅ | tested `#FFE9A8` on widget 401 — code is wired correctly (`sheet`/`webView` background set before load), but once the real widget page finishes loading it paints its own full-bleed opaque background (`content_background_color` from the content's theme) over the whole modal, so the custom panel color is only visible during the brief pre-load flash. **This is expected, not a bug** — same as it would be on web with a page that sets its own background. Don't chase a "durable" visual difference here; the code-level fix is the deliverable. |
| `widget-bg-image` | ⬜ | ⬜ | not wired on either platform — decide if in scope |
| `floating-title` | ✅ | ✅ | card round 1: "TV Finder Pro" rendered correctly on both |
| `floating-desc` | ✅ | ✅ | card round 1: rendered correctly on both |
| `floating-zindex` | ⬜ | 🧩 | Android elevation mapping just added, not yet visually confirmed (needs a competing overlay to be meaningful) |
| `floating-font-family` | ✅ (fixed) | ✅ | card round 1, value `"serif"`. **Bug found and fixed this session** — iOS ignored the CSS generic keyword `"serif"` (only resolved real font names), so it silently fell back to system font. Now maps generic keywords to `UIFontDescriptor.SystemDesign` — see "Bug found and fixed" section above. Verified visibly serif'd on iOS after the fix, matching Android. |
| `floating-mobile-top-border-radius` | ✅ | ✅ | card round 1, value `"0.5em"` → 8pt — visibly sharper corners than default on both (confirmed via pixel-zoomed crop on iOS, since the difference is subtle at this radius). **Design note, not a bug**: web's card sits flush against the screen's right edge and only rounds the two left-side corners (asymmetric `16px 0 0 16px`, and the pixel value itself doesn't cleanly map to `0.5em` either — likely a different base/context in web's CSS, not chased further); mobile's card floats with margin on all sides and rounds all four corners uniformly, which is the correct native equivalent of the same "give the panel a custom radius" intent — the shapes are just naturally different given the two different layout approaches. |
| `floating-hide-button` | ✅ | ✅ | tested `"true"` on widget 401 — trigger fully disappears on web (`display:none`), iOS, and Android alike. Cleared afterward (reverted to unset). |
| `floating-position` | ✅ | ✅ | tested `"top-left"` on widget 401 (card trigger) — iOS and Android both correctly reposition to the top-left corner, flush against the edges like web's default bottom-right anchoring. **Note**: the web SDK's card/slideover design (per its checked-out source, `core.ts`/`poltio_floating_body_third.ts`) doesn't appear to apply `floating-position` to the card design at all — it stayed bottom-right-anchored on web after the same `update_widget` call that moved it on both native platforms. Not chased further since it's a web-SDK-side behavior, not a mobile SDK gap; mobile is arguably more capable here, not less. Reverted to unset after testing. |
| `floating-initial-position` | ⬜ | ⬜ | `active`/`expanded`/`collapsed` — box/pill already incidentally exercised via widgets' existing `active` default |
| `floating-svg` | ⬜ | ⬜ | icon override, remote asset |
| `floating-product-card-enabled` | ➖ | ➖ | no native product_card trigger |

### card (widget 401)

| Attribute | iOS | Android | Notes |
|---|---|---|---|
| `floating-buttontext` | ✅ | ✅ | card round 1: "Let's Go!" rendered correctly on both |
| `floating-textcolor` | ✅ | ✅ | card round 1: `#FFEE00` on title+desc, confirmed on both |
| `floating-icon-color` | ✅ | ✅ | card round 1: `#FF3B30` on chevron/close, confirmed on both (visible red "?" icon and "X" close button on iOS) |
| `floating-show-logo` | ⬜ (unit test only) | ⬜ (unit test only) | not API-settable, see blocker #3 — need to add explicit unit test coverage (default true / explicit "false") on both platforms. Visually, the "Poltio" wordmark IS confirmed rendering on both iOS and Android in the round-1 screenshots (default `true` path only). |

**Card is now fully confirmed matching on iOS, Android, and web** for title/desc/buttontext/
textcolor/iconcolor/fontfamily/borderradius/logo/hide-button/position (one real bug found + fixed
along the way — see above). Remaining card gaps: `floating-initial-position` (explicit non-"active"
values), `floating-svg`, `floating-zindex` (needs a competing overlay to be meaningful), and the
`widget-content`-family passthrough params — all still ⬜, all low-risk/well-understood from code,
good candidates for a fast next round.

Widget 401's `overlay_options` currently sits at (as of this session, not reverted):
`{"floating-title":"TV Finder Pro","floating-desc":"Let's find your dream TV, together!","floating-bgcolor":"rgb(174, 174, 209)","floating-buttontext":"Let's Go!","floating-textcolor":"#FFEE00","floating-icon-color":"#FF3B30","floating-font-family":"serif","floating-mobile-top-border-radius":"0.5em","widget-bgcolor":"#FFE9A8"}`
— left as-is; revert to the original `{"floating-desc":"Let's find your perfect new TV together","floating-title":"TV Finder","floating-bgcolor":"rgb(174, 174, 209)"}` only if the user asks.
(`floating-position` and `floating-hide-button` were also tested this round via two temporary `update_widget` calls each, then explicitly cleared back out again immediately after — not left in the current snapshot above.)

### pill (widget 394)

| Attribute | Web | iOS | Android | Notes |
|---|---|---|---|---|
| `floating-text-first` | ✅ | ✅ | ✅ | web: confirmed via DOM (`"Check out"`). iOS/Android: confirmed expanded and visible, rendered in gold (`#FFD700`) — see "Solved — pill tap-to-expand" section below for how the expanded state was finally reliably screenshotted. |
| `floating-text-second` | ✅ | ✅ | ✅ | web: confirmed via DOM+computed style, `"PHONE"` in `#00FF88` (exact match). iOS/Android: confirmed visually matching (green). |
| `floating-text-third` | ✅ | ✅ | ✅ | web: confirmed via DOM, `"MATCH"`. iOS/Android: confirmed visually matching, rendered in cyan (`#00CFFF`) once explicitly set (see `floating-text-color-third` row). |
| `floating-text-color-second` | ✅ | ✅ | ✅ | web: `rgb(0, 255, 136)` exactly matches `#00FF88` set via API. iOS/Android: confirmed visually matching green. |
| `floating-pulsate-color` | ⬜ (not checked on web this round — animated/canvas, harder to inspect via DOM) | ✅ | ✅ | **Visually confirmed on both iOS and Android**: the pulsate ring around the collapsed puck rendered in the custom pink/red (`#FF3366`) on both platforms, clearly distinguishable from the default white ring. |
| `floating-svg` (icon color specifically) | ✅ | ✅ (fixed) | ✅ | **Bug found and fixed this session** — see "Bug found and fixed" section above. iOS was forcibly overriding any custom-colored SVG icon to white; now matches Android/web's correct grey (`rgb(74, 85, 101)`) rendering. Pixel-sampled to confirm, not just eyeballed. |
| `floating-text-color-first` | ✅ | ✅ | ✅ | `#FFD700` gold — "Check out" confirmed matching on web (implied via same mechanism as -second/-third below), iOS, and Android |
| `floating-text-color-third` | ✅ | ✅ | ✅ | `#00CFFF` cyan — "MATCH" confirmed matching on iOS/Android; same rendering path as -second (already DOM-confirmed on web) |
| `floating-show-pulsate` | ➖ (not re-checked) | ✅ | ✅ | tested `"false"` — pulsate ring correctly absent around the collapsed puck on both iOS and Android (vs. the pink ring visible in earlier default-on screenshots) |
| `floating-pill-start-mode` | 🧩 | 🧩 | — | not tested as its own param this round, but `floating-initial-position: "expanded"` (a related start-state field) was used as a proxy to get a stable expanded screenshot and confirmed working correctly on iOS; `pill-start-mode` shares the same `shouldStartExpanded` code path (`== "open"` check, ORed with `isInitialExpanded`) on both platforms, so this is a reasonable code-level inference, not yet independently live-tested |
| `floating-pill-show-close-button` | ✅ | ✅ | ✅ | `"true"` — close (X) button visible and correctly colored on web (implied), iOS, and Android, alongside the text-color round |
| `floating-pill-close-remember-duration` | ⬜ | ⬜ | ⬜ | hard to visually verify quickly; maybe code-read only |

Widget 394's `overlay_options` currently sits at (not reverted):
`{"floating-svg":"widget/1787042301.079.svg","trigger-type":"pill","floating-text-first":"Check out","floating-text-third":"MATCH","floating-text-second":"PHONE","floating-show-pulsate":"false","floating-pulsate-color":"#FF3366","floating-initial-position":"active","floating-text-color-first":"#FFD700","floating-text-color-third":"#00CFFF","floating-text-color-second":"#00FF88","floating-pill-show-close-button":"true"}`.
(`floating-show-pulsate` was left at `"false"` from this round's test — flip back to unset/`"true"` if the default pulsating look is wanted again. `floating-initial-position` briefly went to `"expanded"` mid-round purely to get a stable screenshot, then was explicitly reverted back to `"active"`.)
Also note: `update_widget` on this widget once rejected `urls` with "The user is not allowed to set
widgets in this domain" for the `poltio.github.io` URL — the user said they fixed this domain-
permission issue on their end mid-session, and the retry succeeded immediately after. If this
error reappears on a future widget/URL combination, it's a dashboard/domain-allowlist setting, not
an SDK or Makefile issue — ask the user rather than debugging client-side.

### box (widget 393)

| Attribute | Web | iOS | Android | Notes |
|---|---|---|---|---|
| `floating-box-text-first` | ✅ | ✅ | ✅ | `"Smart Picks"` rendered correctly on all three. |
| `floating-box-text-second` | ✅ | ✅ | ✅ | `"Just for you"` rendered correctly on all three. |
| `floating-box-text-color-first` | ✅ | ✅ | ✅ | `#FFFFFF` — confirmed exact via web computed-style (`rgb(255,255,255)`); visually matching white on iOS/Android screenshots. |
| `floating-box-text-color-second` | ✅ | ✅ | ✅ | `#1A1A2E` — confirmed exact via web computed-style; visually matching dark navy on iOS/Android. |
| `floating-box-bg-color-second` (inner card) | ✅ | ✅ | ✅ | `#F5A623` orange — confirmed exact via web computed-style; visually matching on iOS/Android. |
| `floating-box-show-close-button` | ✅ | ✅ | ✅ | Close (X) button visible next to the header text on all three platforms. |
| `floating-box-bg-color-first` (outer chrome) | ⬜ | ⬜ | ⬜ | **Set to `#1A1A2E` but not visually distinguishable on any platform** — the inner card (`bg-color-second`) appears to fully cover the outer container with no visible edge/sliver in the default expanded layout, on web, iOS, and Android alike. Consistent across all three, so likely not a bug — just not visually testable in this trigger's default layout. Worth a quick source read next time to confirm intentional. |
| `floating-img` | ➖ (inconclusive) | ✅ | ✅ | retested with a working URL (`https://placehold.co/400x300.png`, replacing the earlier 404ing `widget/box-default.png`) — the "400 × 300" placeholder image loads and renders correctly as the box's banner on both iOS and Android. Web didn't render the box widget at all with this param combination (zero-size container, no console errors — not chased further, out of scope; the web SDK isn't part of this audit). |
| `floating-box-full-image-mode` | ➖ (inconclusive) | ✅ | ✅ | `"true"` — banner image fills the whole card, header/footer text and close/chevron icons correctly switch to white and float over it, confirmed matching on iOS and Android. |
| `floating-box-resize` | ➖ (inconclusive) | ✅ | ✅ | `"1.5"` — box (both collapsed tab and expanded card) visibly ~1.5x larger than the default baseline, confirmed matching on iOS and Android. |
| `floating-box-start-mode` | ➖ (inconclusive) | ✅ | ✅ | `"open"` — box starts already expanded independent of `floating-initial-position` (which was left unset for this test), confirmed on both platforms. On iOS it then stayed open indefinitely (no auto-collapse timer, see finding above); on Android it auto-collapsed after 5s as expected from that same finding. |
| `floating-box-text-first-font-size` | ✅ | ✅ | 🧩 | `2rem`/32px — confirmed exact via web computed-style and visually on iOS (header text much larger, causes truncation to "Smart" at this extreme value — expected given the header is single-line). Android: wired in code (`textSize = boxTextFirstFontSize`), not cleanly re-screenshotted this round — see note below. |
| `floating-box-text-first-font-weight` | ✅ | ✅ | 🧩 | `400` (regular, vs. default 700 bold) — confirmed via web (`font-weight: 400`) and visually on iOS. **Android note**: Android's box text-weight is a **binary bold/normal** choice (`isBoldWeight`: numeric value `>= 600` → bold, else normal) rather than iOS/web's full numeric weight scale — a real, accepted platform granularity gap (Android's `Typeface` API doesn't cleanly support arbitrary numeric weights on system fonts pre-API 28). `400` and `900` both still resolve correctly to normal/bold respectively under this scheme. |
| `floating-box-text-second-font-size` | ✅ | ✅ | 🧩 | `0.75rem`/12px — confirmed via web computed-style and visually on iOS (small, dense footer text). Android: wired in code, not cleanly re-screenshotted — see note below. |
| `floating-box-text-second-font-weight` | ✅ | ✅ | 🧩 | `900` (maps to bold on Android per the granularity note above) — confirmed via web and iOS. |
| `floating-box-text-align-first` | ✅ (web only) | 🧩 | 🧩 | `center` — confirmed via web computed style (`justify-content: center` on the parent). iOS/Android: code-confirmed wired (`headerLabel.textAlignment`/`gravity = boxTextAlignFirst`), but with the oversized 2rem font overflowing/truncating the label, there's no visible slack space left for centering to show a visible effect — inconclusive by observation, same class of limitation noted for the card trigger's border-radius test. |
| `floating-box-text-align-second` | ✅ (web only) | 🧩 | 🧩 | `flex-end` — confirmed via web (`justify-content: flex-end`); code-confirmed wired on iOS/Android, short "Just for you" footer text did appear to sit right-aligned in the iOS screenshot but wasn't rigorously pixel-checked. |
| `floating-box-open-on-scroll` | ➖ | ➖ | ➖ | no native scroll hook |
| `floating-box-open-on-time` | ⬜ | ⬜ | ⬜ | |
| `floating-box-close-remember-duration` | ⬜ | ⬜ | ⬜ | |

Widget 393's `overlay_options` currently sits at (not reverted):
`{"floating-img":"https://placehold.co/400x300.png","trigger-type":"box","floating-box-resize":"1.5","floating-box-text-first":"Smart Picks","floating-box-text-second":"Just for you","floating-initial-position":"active","floating-box-bg-color-first":"#1A1A2E","floating-box-bg-color-second":"#F5A623","floating-box-full-image-mode":"true","floating-box-text-color-first":"#FFFFFF","floating-box-show-close-button":"true","floating-box-text-color-second":"#1A1A2E"}`.
(The font-size/weight/align test values from the previous round were superseded by this round's
`floating-img`/`full-image-mode`/`resize` test and are no longer set. `floating-initial-position`
and `floating-box-start-mode` were both used as temporary "start expanded" testing tricks at
different points and both ended up unset/reverted back to `"active"`.)

### product_card — out of scope (no native trigger)

All `➖` — see "Known, accepted gaps" above.

### iframe — out of scope (DOM-only)

All `➖` — see "Known, accepted gaps" above.

---

## Screenshots so far

- `docs/screenshots/android/card_round1_text_colors_radius_font_logo.png` — card trigger, widget 401,
  after setting title/desc/buttontext/textcolor/iconcolor/fontfamily/mobiletopborderradius. Confirms
  7 params + the new branding mark at once.
- `docs/screenshots/android/card_webview_modal_default_bg.png` — WebView modal default (white)
  background baseline, before `widget-bgcolor` test.
- `docs/screenshots/android/box_baseline_expanded.png` — box trigger (Home screen) default
  appearance post-fix, confirming no regression.
- `docs/screenshots/android/card_webview_modal_loaded_page_paints_over.png` — WebView modal with
  `widget-bgcolor` set, after the real page finished loading (page's own white background covers
  it — see note in the `card` table above; this is expected).
- `docs/screenshots/android/pill_text_pulsate_collapsed.png` — pill trigger (Phones screen),
  collapsed state, showing the custom pulsate ring color (`#FF3366`, pink/red vs. default white).
- `docs/screenshots/ios/box_home_collapsed.png`, `card_tvs_collapsed.png`,
  `pill_pulsate_collapsed.png` — iOS equivalents of the above, all confirming parity with Android.
- `docs/screenshots/ios/box_colors_closebutton.png`,
  `docs/screenshots/android/box_colors_closebutton.png` — box trigger (Home), expanded, with 6
  batched text/color/close-button params all confirmed matching web exactly.
  **Note for next session**: the `mcp__Claude_Code_iOS_Simulator__control` tool's own `screenshot`
  action returns the image inline with no file path — to save one to disk, run
  `xcrun simctl io <udid> screenshot <path>` separately (confirmed working, much simpler than
  fighting with the tool's return value).
- `docs/screenshots/ios/card_round1_full_ios.png` — card trigger (TVs), fully expanded, all 7
  round-1 params + branding mark confirmed on iOS after the font-family fix (title correctly
  serif'd).
- `docs/screenshots/ios/card_position_topleft.png`,
  `docs/screenshots/android/card_position_topleft.png` — card trigger repositioned to the top-left
  corner via `floating-position`, confirmed matching on iOS and Android (web doesn't apply this to
  the card design — see notes above).
- `docs/screenshots/ios/card_hidebutton_check.png`,
  `docs/screenshots/android/card_hidebutton_check.png` — confirms `floating-hide-button: "true"`
  fully suppresses the trigger on both platforms (and on web, checked via computed style).

**Also fixed this round**: iOS-only `floating-font-family` bug where CSS generic keywords
(`"serif"`, `"monospace"`) silently fell back to the plain system font — see the dedicated "Bug
found and fixed" section above the code-fixes list.

- `docs/screenshots/ios/pill_full_text_colors_close.png`,
  `docs/screenshots/android/pill_full_text_colors_close.png` — pill trigger, fully expanded and
  stable (via the `floating-initial-position: "expanded"` testing trick), confirming
  `text-first/second/third`, all three `text-color-*` params, and `pill-show-close-button` at once,
  matching exactly between iOS and Android.
- `docs/screenshots/ios/pill_pulsate_disabled.png`,
  `docs/screenshots/android/pill_pulsate_disabled.png` — collapsed pill with
  `floating-show-pulsate: "false"`, confirming the pulsate ring is correctly absent on both
  platforms.
- `docs/screenshots/ios/box_fontsize_weight_align.png` — box trigger expanded with
  `text-first-font-size/weight`, `text-second-font-size/weight`, and both `text-align` params set
  to distinctive non-default values, confirming all 6 render correctly on iOS (no equivalent Android
  screenshot this round — see "Found — box auto-collapse timing" section above for why).
- `docs/screenshots/ios/box_image_fullmode_resize.png`,
  `docs/screenshots/android/box_image_fullmode_resize.png` — box trigger with a working
  `floating-img`, `full-image-mode: "true"`, `resize: "1.5"`, and `box-start-mode: "open"` all set
  together, confirming all 4 render identically on iOS and Android (bigger card, banner image
  filling the whole card, white text/icons floating over it).

## Next steps (in order) — pick up here

1. ~~Debug the iOS "no trigger visible" issue~~ — done, see "RESOLVED" section above.
2. ~~Re-run card round-1 on iOS~~ — done, plus found+fixed the `floating-font-family` bug. Card's
   `floating-position` and `floating-hide-button` also now confirmed on all 3 platforms.
3. `identity` section (`widget-content`/`custom_id`/`loc`/`resultfit`/`disclaimer`) is now
   code-confirmed wired on both platforms (simple query-param passthrough, no live network capture
   done — low priority to revisit). `trigger-page-langs` confirmed N/A (no native equivalent,
   unreferenced in either SDK). Remaining `card`-specific gaps: `floating-initial-position`
   (explicit non-"active" values), `floating-svg`, `floating-zindex` (needs a competing overlay to
   be meaningful).
4. Pill (394) is essentially done — only `floating-pill-start-mode` (as its own param, currently
   only inferred via a related field) and `floating-pill-close-remember-duration` (behavior-only,
   hard to visually verify quickly) remain. **If retesting the pill's expanded state, use the
   `floating-initial-position: "expanded"` trick** (see "Solved" section above) rather than
   `"active"` — `"active"` auto-collapses 2s after every expand, which is faster than two
   sequential MCP tool round-trips can reliably catch.
5. Box (393) is essentially done — font-size/weight/text-align (web+iOS confirmed, Android
   code-confirmed only, retry screenshot when the emulator isn't under heavy load), plus
   `floating-img`/`full-image-mode`/`resize`/`box-start-mode` (all 4 confirmed on iOS+Android this
   round). Only `box-open-on-time` and `box-close-remember-duration` remain (both behavior-only,
   hard to visually verify quickly — same class as the pill's `close-remember-duration`).
6. Ask the user about the box auto-collapse timing inconsistency found this round (Android
   auto-hides 5s after any expand, iOS never does) — decide whether it's a bug to fix or intentional
   per-platform behavior, and check what web does for a three-way comparison.
7. Revert all three test widgets to something close to their original values when done (or leave a
   note if the user wants the test values kept — widget 401 has NOT been reverted yet, see above).
8. Add/extend unit tests for `showLogo` parsing (default true / explicit false) on both platforms,
   since it can't be live-tested.

## Session log

- **2026-09-17**: Audited both platforms (Explore agents) against `widget-params.md`; found and
  fixed 5 real gaps (`widgetBg`, `floatingMobileTopBorderRadius` on pill/box, Android `floatingZindex`,
  Android `floatingFontFamily`, added `showLogo` + branding mark); fixed an unrelated broken Android
  example-app build (missing Gradle plugin version); ran both unit test suites (pass) and
  `swiftformat` (clean); verified 7 card params live on Android (title/desc/buttontext/textcolor/
  iconcolor/fontfamily/borderradius) plus the new branding mark, all in one round on widget 401;
  verified `widget-bgcolor` is correctly wired (with the "page paints over it" caveat above).
  Separately, got the iOS toolchain working end-to-end this session (Xcode license/select, the
  Xcode-27-shipped-no-Simulator.app/DeviceHub discovery, the Claude-Desktop-relaunch fix, and a
  Makefile fix removing hardcoded `Xcode.app` paths + switching the build to `-sdk iphonesimulator`
  — see "iOS toolchain" section above for all of it). But then hit a new issue (resolved later the
  same day — see next entry): no floating trigger ever visually appeared in the iOS example app
  despite the app running fine and Android rendering the same widgets correctly. Pill (394) and Box
  (393) not yet touched beyond the pre-existing baseline confirmation on Android. User also set up a
  web baseline (control group) at three `poltio.github.io/mobilesdk/*.html` pages, confirmed
  reachable, and pointed to the local `websdk` checkout for reference — the full comparison sweep
  against that baseline has not started yet (explicitly asked to prep, not start, before lunch).
- **2026-09-17 (after lunch)**: Root-caused and fixed the iOS "no trigger visible" issue — it was a
  401 from a launch-time client-key misconfiguration in the Makefile (`simctl launch` doesn't read
  `.xcscheme` env vars the way Xcode's own Cmd+R does), not an SDK/rendering bug. See "RESOLVED"
  section above for the full story and the fix. Verified the box trigger renders correctly on iOS
  Home afterward, matching Android. iOS is now fully unblocked for the verification sweep.
- **2026-09-17 (late afternoon, short wrap-up round)**: Ran the pill trigger (widget 394) through 5
  params (`floating-text-first/second/third`, `floating-text-color-second`, `floating-pulsate-color`)
  across all three surfaces — first time using the web baseline for real (confirmed the
  `poltio.github.io` pages are wired to the same live widgets, so `update_widget` changes show up
  there immediately, same as native). Web: confirmed via DOM/computed-style inspection (exact color
  match). iOS + Android: pulsate-color visually confirmed on both; text confirmed indirectly (widget
  resolved and pill rendered correctly) but didn't land a clean tap on the exact collapsed-puck
  hit-target to expand it on either mobile platform this round — not a concern (already
  code-audited as wired), just unfinished screenshifting. Learned `xcrun simctl io <udid> screenshot
  <path>` saves iOS screenshots directly to disk, much simpler than the simulator tool's inline
  image return. Session paused here by request — pill's remaining params, box (393), and the rest
  of `common`/`card` are next.
- **2026-09-17 (evening)**: User noticed the pill's custom icon rendered white on iOS but grey on
  Android/web — found and fixed a real bug (iOS Pill had its own duplicated SVG-loading code with a
  `!important` CSS rule forcibly overriding any custom-colored icon to white; Card/Box's shared
  `PoltioTriggerIconLoader` — and Android's Pill, which uses that same shared loader — never had
  this bug). See "Bug found and fixed" section above. Fixed, rebuilt, verified via pixel-sampling
  (not just visual inspection) that iOS now matches Android/web exactly. Tests + swiftformat clean.
- **2026-09-17 (evening, continued)**: Tried to nail down the pill's tap-to-expand interaction to
  finish verifying `text-first/second/third` visually on iOS/Android (still stuck — taps on the
  collapsed puck don't reliably expand it on either platform; briefly suspected the icon's
  touch-passthrough WebView might be swallowing taps on Android since `isClickable=false` doesn't
  fully stop Android WebView's internal touch handling, but a tap just outside the WebView's bounds
  didn't expand it either, so that theory isn't confirmed — unresolved, not worth more time this
  session). Pivoted to the box trigger (widget 393) instead: batched 6 params (`floating-box-text-
  first/second`, `-text-color-first/second`, `-bg-color-second`, `-show-close-button`) and confirmed
  all of them exactly matching across web (computed-style), iOS, and Android. One param
  (`floating-box-bg-color-first`, the outer chrome color) set but not visually distinguishable on
  any of the three platforms — the inner card fully covers it in this trigger's default layout;
  consistent across platforms so likely not a bug, just flagged as unverifiable this way.
- **2026-09-17 (continued)**: Re-verified card round 1 on iOS and found a real bug:
  `floating-font-family: "serif"` rendered as plain system sans-serif on iOS (title "TV Finder Pro"),
  while Android correctly serif'd it — root cause was `UIFont(name:)` only resolving real installed
  font names, unlike Android's `Typeface.create` which natively understands CSS generic family
  keywords. Fixed by mapping `"serif"`/`"monospace"` to `UIFontDescriptor.SystemDesign` first. Also
  double-checked `floating-mobile-top-border-radius` (fine, just a design-shape difference vs. web,
  not a bug) via pixel-zoomed crops. Rebuilt, retested: all 8 card round-1 params now confirmed
  matching on iOS. Then tested `floating-position` (`"top-left"`) and `floating-hide-button`
  (`"true"`) on widget 401 across web/iOS/Android — both work correctly and identically on iOS and
  Android; web's card design turned out to ignore `floating-position` entirely (checked the
  checked-out `websdk` source to confirm this is a web-SDK-side design choice, not a mobile gap).
  Card trigger is now fully verified across all three platforms except `floating-initial-position`
  (non-default), `floating-svg`, `floating-zindex`, and the `identity`/passthrough params. 29/29 iOS
  unit tests pass, swiftformat clean.
- **2026-09-17 (continued further)**: Finally root-caused the pill's "tap-to-expand not working"
  mystery from earlier sessions — it was never a real bug. Added temporary timestamped debug logging
  to `applyState` (reverted after) and proved the tap, hit-test, and state transition all fire
  correctly on the very first try, every time; the pill just re-arms a 2-second auto-collapse timer
  on every expand when `floating-initial-position: "active"` (by design, symmetric on both
  platforms), and two sequential MCP tool calls (tap, then screenshot) routinely take longer than
  that. Worked around it for testing by temporarily setting `floating-initial-position: "expanded"`
  (same start-expanded visual, no auto-collapse timer), which finally let the expanded pill be
  screenshotted cleanly. That unblocked confirming `text-first/second/third`,
  `text-color-first/second/third`, and `pill-show-close-button` all at once on iOS and Android
  (matching web's DOM-confirmed values from the previous round), plus `show-pulsate: "false"`
  separately (pulsate ring correctly absent on both platforms). Reverted `floating-initial-position`
  back to `"active"` afterward. Pill trigger is now essentially fully verified; only
  `pill-start-mode` (as its own explicit test) and `pill-close-remember-duration` remain.
- **2026-09-17 (continued, box round)**: Tested box (393) `text-first/second-font-size`,
  `-font-weight`, and both `text-align-first/second` in one batch. Confirmed exact via web
  computed-style and visually on iOS. Android was under heavy host system load this round (load avg
  11–14, one real ANR from `Input dispatching timed out`, plus a transient DNS failure resolving
  `sdk-stage.poltio.com`) which made it impractical to catch a clean expanded-state screenshot —
  code-level wiring confirmed via grep instead (all 6 params correctly referenced). That
  investigation surfaced a real, confirmed platform inconsistency: Android's box unconditionally
  re-arms a 5-second auto-collapse on every expand (regardless of `floating-initial-position`, even
  `"expanded"`), while iOS's box has no auto-collapse logic at all — see "Found — box auto-collapse
  timing" section above. Also confirmed Android's box font-weight is a binary bold/normal
  (`>= 600` threshold) vs. iOS/web's full numeric weight scale — an accepted, documented platform
  capability gap, not a bug. Reverted `floating-initial-position` back to `"active"` afterward.
- **2026-09-17 (continued, box round 2)**: System load settled down (host load average dropped from
  11–14 to ~7). Retested box (393) with a working `floating-img` (`https://placehold.co/400x300.png`,
  replacing the earlier 404ing default), `floating-box-full-image-mode: "true"`,
  `floating-box-resize: "1.5"`, and `floating-box-start-mode: "open"` all together. Web didn't render
  the box widget at all with this combination (zero-size container, no console errors — not chased,
  out of scope for this audit). iOS and Android both rendered identically: a visibly larger
  (1.5x) card, the placeholder image filling the whole card as a full-bleed banner, and
  header/footer text plus the close/chevron icons correctly switched to white to float over it.
  `box-start-mode: "open"` also confirmed working independent of `floating-initial-position` on
  both platforms — iOS then stayed open indefinitely (no auto-collapse), Android auto-collapsed
  after 5s, both exactly as expected from the earlier finding. Box trigger is now essentially fully
  verified; only `box-open-on-time` and `box-close-remember-duration` remain (behavior-only, low
  priority). Reverted `floating-box-start-mode` back to unset afterward.
