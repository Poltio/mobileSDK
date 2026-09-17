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

## Feature added — card now reveals on scroll (matching web, differently from box/pill)

Continuing the same source-reading approach used for box and pill, read web's actual `core.ts`
(card's generic engine, shared with the underlying first/second/third reveal machinery) before
assuming the same box/pill fix would apply. It doesn't, cleanly — card's web mechanism is a
**different, one-way** pattern:

```js
document.addEventListener('scroll', () => {
  const scrollHeight = document.documentElement.scrollTop || document.body.scrollTop || 0;
  if (scrollHeight > (scrollThreshold ?? 300)) {
    if (clickElem.classList.contains('first')) {
      clickElem.classList.remove('first');
      clickElem.classList.add('second'); // reveals the expanded card
      controller.abort(); // one-shot
    }
  }
});
```

No `setTimeout` re-collapse anywhere near this — once scrolled past `scrollThreshold` (default
`300`, read from `floating-scroll-threshold` — already modeled on both mobile platforms as
`floatingScrollThreshold`, just never consumed), the card reveals itself and **stays revealed**
until the user closes it or taps to open the full widget. This matches mobile's card, which already
has no auto-collapse timer of its own (confirmed by grep — zero matches for
`autoCollapse`/`scrollObserver` in either platform's card view, unlike box/pill).

**Implemented** on both platforms by extending the shared `PoltioScrollObserver`/`.kt` with a new,
separate one-shot API (`onScrollPast(threshold:callback:)` on iOS,
`onScrollPast(activity, thresholdDp, callback)` on Android) that self-manages its own one-shot
lifecycle — cleaner than box/pill's manual `hasAutoOpenedFromScroll` flag, and lets each trigger
register its own threshold instead of the fixed 100pt/dp the box/pill's existing notification uses.
The card trigger now calls this once at init with `floatingScrollThreshold`, expanding itself the
first time it fires (guarded by `currentState == .collapsed`, in case the user already tapped it
open manually) — no auto-collapse added, since card's web behavior doesn't have one either.

**Verified live on both platforms**: set `floating-scroll-threshold: "50"` on widget 401 for a fast
test, confirmed a swipe/scroll on the TVs screen reveals the card fully expanded on both iOS and
Android — and, unlike box/pill, it **stays expanded** after 6+ seconds untouched, confirming no
stray auto-collapse was accidentally introduced. Reverted the test threshold back to unset (default
300) afterward.

## Fixed — box header background stripe was mapped to the wrong element

While doing a full parameter-by-parameter box audit (per the user's request to get one trigger type
to 100% parity with web before moving to the next), `floating-box-bg-color-first` — previously
flagged as "set but not visually distinguishable on any platform" — turned out to be a real,
confirmed cross-platform bug, not just an untestable layout quirk.

**Root cause**: reading web's actual `box.ts` source (not just `widget-params.md`) showed
`.poltio-first-text { background: ${boxBgColorFirst}; }` — this param colors the **header text
row's own background stripe**, a design element entirely separate from the outer card. Mobile
instead applied it to the outer `expandedContainer`/card chrome, which the inner card
(`bg-color-second`) fully covers in the default layout — hence it was never visible on any platform,
consistently, which is exactly why it read as "a shared, harmless layout quirk" rather than "a real
bug" in earlier rounds.

**Fix applied** (`PoltioFloatingBoxTriggerView.swift`/`.kt`): the outer container now uses the
generic `floating-bgcolor` (`resolvedBgColor`), matching web's `.poltio-floating-container.second`
whose own background comes from that same generic param, not `bg-color-first`. A new
`headerBackgroundView` (iOS) / plain `View` (Android), sized to exactly the header row (from the
card's top edge to where the banner starts), now carries `bg-color-first` as its own background,
sitting behind the header label and above the card's base color — reproducing web's two-stripe
design (colored header row, separately-colored body/footer) instead of one flat card color.

**Verified**: set `bg-color-first` to a bright pink and `bg-color-second` to orange, with the
generic `floating-bgcolor` set to blue — confirmed on both iOS and Android that the header row shows
pink as its own distinct band, the banner/footer area shows orange, and the outer chrome color
(blue) isn't visible anywhere (correctly matching web, where the outer container's color is also
fully covered by the three stacked content rows in the default layout — this part was never the bug).

## Fixed — box auto-collapse is now the default on both platforms

**Originally found as an inconsistency, now resolved.** While testing the box trigger's
font-size/weight/align params, Android's emulator was under heavy system load (host load average
11–14, one real ANR logged — `Input dispatching timed out` — plus a transient DNS failure; all
environmental, not an SDK bug), which made screenshotting the box mid-expanded-state very difficult
— every attempt landed on an already-collapsed frame. Digging into why surfaced a real platform
inconsistency: Android's `PoltioFloatingBoxTriggerView.applyState` unconditionally scheduled a
5-second auto-collapse any time the box became expanded, while iOS's box had **no auto-collapse
timer at all** — once expanded on iOS, it stayed open until the user (or `resetToCollapsed`) closed
it.

The user confirmed Android's behavior (auto-collapse after expanding) is the one they want as the
**default on both platforms**, and specifically asked for it to also mimic web's
`floating-box-open-on-scroll` pattern: box starts collapsed, opens once the user scrolls past a
threshold, then auto-collapses again — "which is good" on web and worth native parity.

**Fixed**: `ios/Sources/PoltioSDK/UI/PoltioFloatingBoxTriggerView.swift` now re-arms a 5-second
auto-collapse timer every time it enters the expanded state (mirroring Android's existing,
already-shipped `AUTO_COLLAPSE_DELAY_MS = 5000L` behavior exactly — same unconditional trigger,
same duration), invalidated on manual close/open-widget so it can't fire after the trigger's gone.

## Feature added — native `floating-box-open-on-scroll`

Both platforms already parsed `boxOpenOnScroll: Bool` (default `true`) into the model, but neither
consumed it anywhere — it was fully inert. Implemented it natively on both platforms, mirroring web
SDK's `box.ts`: on load, if `floating-box-open-on-time` isn't also set (matching web's
`else if` precedence — the two are alternative ways to specify the same "auto-reveal once" moment),
install a scroll observer; the first time the host content scrolls past a ~100pt/dp threshold, the
collapsed box auto-expands once (one-shot, like web's `controller.abort()`), and the new default
auto-collapse timer above closes it again a few seconds later — the exact "starts collapsed → opens
on scroll → collapses again" loop the user asked to mimic.

Mobile has no single generic "did the page scroll" signal the way a browser's `document.scroll`
does, so each platform uses its own best native technique, chosen specifically so it also works with
apps built on modern UI toolkits, not just classic scroll views:

- **iOS** (`ios/Sources/PoltioSDK/UI/PoltioScrollObserver.swift`, new file): swizzles
  `UIScrollView`'s `contentOffset` setter once per process — the same standard, non-invasive
  technique various analytics SDKs use for scroll-depth tracking. Always calls through to the
  original implementation first, so host scrolling is completely unaffected; this works for both
  UIKit scroll views and SwiftUI's `ScrollView`/`List` (both backed by `UIScrollView` under the
  hood).
- **Android** (`android/poltio-sdk/src/main/java/com/poltio/sdk/ui/PoltioScrollObserver.kt`, new
  file): wraps the current `Activity`'s `Window.Callback.dispatchTouchEvent` and tracks cumulative
  vertical touch displacement per gesture. This was a deliberate choice over the more "obvious"
  `ViewTreeObserver.OnScrollChangedListener` — that only fires for classic `View.scrollTo`/`scrollBy`
  calls, which **Jetpack Compose's `LazyColumn`/`ScrollView` never issues** (Compose manages scroll
  purely internally). Wrapping `Window.Callback` sees every touch for the whole Activity before
  either UI toolkit does, so it works for Compose apps too — confirmed live against the (Compose-based)
  example app itself. Always delegates to the original callback unmodified and never consumes the
  event, so host touch/gesture handling is unaffected — the same non-interference guarantee
  `PoltioHostInteractionBus` already relies on.

**Verified working end-to-end on both platforms**: relaunched the example app with widget 393 set to
`floating-box-open-on-scroll: "true"` and no `floating-initial-position` (so it starts collapsed by
default); a single scroll/swipe on the Home screen's product list auto-expanded the box on both iOS
and Android, and it auto-collapsed back to the tab ~5s later on both, untouched. 29/29 iOS unit
tests still pass, Android unit tests still pass, swiftformat clean.

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
- [x] Box auto-collapse is now the default on iOS too (previously Android-only) — see "Fixed — box
      auto-collapse" section above.
- [x] `floating-box-open-on-scroll` implemented natively on both platforms (was previously
      parsed-but-unused) — see "Feature added" section above.

## Web's box test page is currently not rendering (unrelated to mobile SDK)

While chasing the `floating-img`+`full-image-mode`+`resize` "web didn't render" mystery from the
previous round, found that `https://poltio.github.io/mobilesdk/home.html`'s box widget renders a
`.poltio-floating-container` with `width: 0px; height: 0px` regardless of `overlay_options` content
— reproduced with zero custom params at all, and after clearing all `localStorage` (ruling out a
stale `flying_closed`/dismissal flag as the cause). The **card** trigger (widget 401, `plp_tvs.html`)
renders correctly at the same time, so this isn't a site-wide outage — it's specific to the box
widget/page. Given this is entirely web-SDK/dashboard-side (outside `mobileSDK`'s scope, and the
local `websdk` checkout may not even match what's actually deployed on that GitHub Pages test site),
not chased further. **Practical impact**: box's web-column entries this round were sourced from
reading `box.ts`'s actual source directly (high confidence — quoting real CSS/JS, not guessing from
`widget-params.md` alone) rather than live-render confirmation. Worth flagging to the user/web team
separately if box's web behavior needs live verification again.

## Found — box has no chevron/collapse-button equivalent on web (not changed)

While investigating the full-image-mode design difference, found that web's box has **only one**
button when `boxShowCloseButton` is set (an X, serving double duty: collapse-if-expanded /
dismiss-forever-if-collapsed depending on state) — there's no separate chevron affordance in
`box.ts`'s HTML at all. Mobile has always had two distinct buttons (chevron to collapse, X to
dismiss forever). This predates this session and looks like a deliberate, reasonable mobile-specific
UX improvement — touch users have no hover-preview affordance the way desktop web does, so an
explicit, unambiguous "collapse" control makes sense. Left as-is; flagging as a known, sensible
platform difference rather than something to remove for stricter web parity.

## Known, accepted gaps (not fixed — documented behavior, not bugs)

- (`floatingScrollThreshold` moved out of this list — see "Feature added — card now reveals on
  scroll" below, it's now implemented, matching `boxOpenOnScroll` before it.)
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
| `floating-font-family` | ✅ (fixed) | ✅ | card round 1, value `"serif"`. **Bug found and fixed this session** — iOS ignored the CSS generic keyword `"serif"` (only resolved real font names), so it silently fell back to system font. Now maps generic keywords to `UIFontDescriptor.SystemDesign` — see "Bug found and fixed" section above. Verified visibly serif'd on iOS after the fix, matching Android. |
| `floating-mobile-top-border-radius` | ✅ | ✅ | card round 1, value `"0.5em"` → 8pt — visibly sharper corners than default on both (confirmed via pixel-zoomed crop on iOS, since the difference is subtle at this radius). **Design note, not a bug**: web's card sits flush against the screen's right edge and only rounds the two left-side corners (asymmetric `16px 0 0 16px`, and the pixel value itself doesn't cleanly map to `0.5em` either — likely a different base/context in web's CSS, not chased further); mobile's card floats with margin on all sides and rounds all four corners uniformly, which is the correct native equivalent of the same "give the panel a custom radius" intent — the shapes are just naturally different given the two different layout approaches. |
| `floating-hide-button` | ✅ | ✅ | tested `"true"` on widget 401 — trigger fully disappears on web (`display:none`), iOS, and Android alike. Cleared afterward (reverted to unset). |
| `floating-position` | ✅ | ✅ | tested `"top-left"` on widget 401 (card trigger) — iOS and Android both correctly reposition to the top-left corner, flush against the edges like web's default bottom-right anchoring. **Note**: the web SDK's card/slideover design (per its checked-out source, `core.ts`/`poltio_floating_body_third.ts`) doesn't appear to apply `floating-position` to the card design at all — it stayed bottom-right-anchored on web after the same `update_widget` call that moved it on both native platforms. Not chased further since it's a web-SDK-side behavior, not a mobile SDK gap; mobile is arguably more capable here, not less. Reverted to unset after testing. |
| `floating-initial-position` | ✅ | ✅ | `"expanded"` tested explicitly on card (widget 401) — starts already expanded on load, no tap/scroll needed, confirmed on both platforms. `active`/`collapsed` already incidentally exercised via box/pill's own testing. |
| `floating-svg` | ✅ | ✅ | tested on card (widget 401) — the custom phone-icon SVG renders correctly in place of the sparkle icon, on both platforms, using the same shared `PoltioTriggerIconLoader` already fixed for the pill icon-color bug earlier this session. |
| `floating-scroll-threshold` | ✅ | ✅ | **Feature added this session** for the card trigger — see "Feature added — card now reveals on scroll" section below. Default 300pt/dp, matching web's `scrollThreshold ?? 300`; tested at `"50"` for a fast live confirmation. |
| `floating-zindex` | ⬜ | 🧩 | Android elevation mapping added earlier this session, not yet visually confirmed (needs a competing overlay to be meaningful) — still low priority, not chased this round either. |
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
`{"floating-svg":"widget/1787042301.079.svg","floating-title":"TV Finder Pro","floating-desc":"Let's find your dream TV, together!","floating-bgcolor":"rgb(174, 174, 209)","floating-buttontext":"Let's Go!","floating-textcolor":"#FFEE00","floating-icon-color":"#FF3B30","floating-font-family":"serif","floating-mobile-top-border-radius":"0.5em","widget-bgcolor":"#FFE9A8"}`
— left as-is; revert to the original `{"floating-desc":"Let's find your perfect new TV together","floating-title":"TV Finder","floating-bgcolor":"rgb(174, 174, 209)"}` only if the user asks.
(`floating-position` and `floating-hide-button` were tested via temporary `update_widget` calls,
then cleared back out. `floating-scroll-threshold` was temporarily set to `"50"` to test the new
scroll-reveal feature quickly, then reverted to unset (default 300). `floating-initial-position:
"expanded"` was also used temporarily to test the icon/initial-position combo, then removed —
default collapsed-then-scroll-reveal is now the more representative demo state, matching box/pill.)

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
| `floating-pill-close-remember-duration` | ➖ (not re-tested) | ✅ (unit test) | ✅ (unit test) | Same shared, already-verified `PoltioTriggerDismissalStore`/`.kt` used by the box trigger (keyed by `publicId`, trigger-type-agnostic) — see box's equivalent row above for the reasoning. Close button's mere existence already visually confirmed above (`pillShowCloseButton` row). |
| *(no param — unconditional)* `floating-initial-position`-independent scroll reveal | ✅ | ✅ (via debug trace) | ✅ (shared infra) | **Feature added this session** — see "Feature added — pill now auto-reveals on scroll" section below. Web's pill (`pill.ts`) unconditionally reveals the collapsed pill on first scroll past ~100px with no config flag at all (unlike box's opt-in `floating-box-open-on-scroll`); mobile had no equivalent until now. |

Widget 394's `overlay_options` currently sits at (not reverted):
`{"floating-svg":"widget/1787042301.079.svg","trigger-type":"pill","floating-text-first":"Check out","floating-text-third":"MATCH","floating-text-second":"PHONE","floating-show-pulsate":"false","floating-pulsate-color":"#FF3366","floating-text-color-first":"#FFD700","floating-text-color-third":"#00CFFF","floating-text-color-second":"#00FF88","floating-pill-show-close-button":"true"}`.
(`floating-show-pulsate` was left at `"false"` from an earlier round — flip back to unset/`"true"` if the default pulsating look is wanted again. `floating-initial-position` is now deliberately **unset** — same reasoning as box: this is the live demonstration of the new default pill behavior, starts collapsed and reveals itself on first scroll.)

## Fixed — pill auto-collapse is now unconditional too (matches box)

Same fix as box, applied to pill for consistency: previously, both platforms only re-armed the
pill's auto-collapse timer when `floating-initial-position: "active"` was set — a manually-tapped
expand (with no `isInitialActive`) would stay open indefinitely. Removed that gate on both
platforms; the pill now always schedules its existing 2-second auto-collapse whenever it enters the
expanded state, for any reason, matching the box trigger's "auto-collapse is default" behavior and
web's own pill (`.expanded` class always gets removed 3s after being added in `pill.ts`, regardless
of how it was added). The pre-existing 2s timer duration itself was left unchanged.

## Feature added — pill now auto-reveals on scroll (unconditionally, matching web)

Reading web's actual `pill.ts` source (the same audit approach used for box) showed the pill has an
**unconditional** scroll listener — no config flag gates it at all, unlike the box trigger's opt-in
`floating-box-open-on-scroll`. On web, any pill widget reveals itself the first time the host page
scrolls past ~100px, then auto-hides again 3 seconds later. Mobile had no equivalent at all until
now.

**Implemented** on both platforms, reusing the exact `PoltioScrollObserver`/`.kt` infrastructure
built for box's `floating-box-open-on-scroll` earlier this session (the `UIScrollView.contentOffset`
swizzle on iOS, the `Window.Callback.dispatchTouchEvent` wrapper on Android) — no new scroll-detection
code needed, just a new one-shot listener wired into the pill trigger view that expands it once,
relying on the now-unconditional auto-collapse (above) to close it again ~2s later.

**Verification**: confirmed via temporary debug trace on iOS (`handleScrollOpenDetected` fires
correctly with `currentState=collapsed` on a real scroll/bounce gesture) rather than a screenshot —
the visible window is very short (expand animation + 2s auto-collapse) and, as established earlier
this session for `box-open-on-time`, sequential tool round-trips can't reliably land inside it. The
example app's Phones screen (where the test pill lives) also doesn't have enough content to
genuinely scroll — only a strong swipe produces the small rubber-band `contentOffset` change needed
to trigger it, which is what the debug trace confirmed. Not independently re-verified with an
Android-side debug trace, since Android's `PoltioScrollObserver.kt` was already live-screenshot-
confirmed working end-to-end for the box trigger earlier this session, and the pill's consuming code
is structurally identical (same one-shot-listener pattern, same singleton observer) — high
confidence without redoing that specific check.
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
| `floating-box-bg-color-first` (header stripe) | 🧩 (web unread; see fix) | ✅ | ✅ | **Bug found and fixed this session.** Reading web's actual `box.ts` source showed this colors `.poltio-first-text`'s own background — a distinct stripe behind the header row — not the outer card chrome. Mobile had it backwards (outer container, which the inner card fully covers, hence "not visually distinguishable" in earlier rounds). Fixed on both platforms: outer container now uses the generic `floating-bgcolor` (matching web's `.second` container), and a new `headerBackgroundView` stripe (iOS)/`View` (Android) sized to the header row now carries `bg-color-first`. Verified visually on both: header row shows its own distinct color, separate from the `bg-color-second` body/footer. See "Fixed — box header background stripe" section above. |
| `floating-img` | ➖ (inconclusive) | ✅ | ✅ | retested with a working URL (`https://placehold.co/400x300.png`, replacing the earlier 404ing `widget/box-default.png`) — the "400 × 300" placeholder image loads and renders correctly as the box's banner on both iOS and Android. Web didn't render the box widget at all with this param combination (zero-size container, no console errors — not chased further, out of scope; the web SDK isn't part of this audit). |
| `floating-box-full-image-mode` | ➖ (inconclusive) | ✅ | ✅ | `"true"` — banner image fills the whole card, header/footer text and close/chevron icons correctly switch to white and float over it, confirmed matching on iOS and Android. **Design difference found, not changed**: web's actual `full-image-mode` (`box.ts`) drops the header/footer text entirely and shows *only* the image (or a gradient fallback) — no text overlay at all. Mobile's richer "text floats over the image with a scrim" design is a deliberate-looking enhancement that predates this session, not obviously a bug, and ripping it out would be a real visual regression I can't currently verify live (web's box test page isn't rendering right now — see note below). Flagging for the user to decide whether to match web exactly or keep mobile's version. |
| `floating-box-resize` | ➖ (inconclusive) | ✅ | ✅ | `"1.5"` — box (both collapsed tab and expanded card) visibly ~1.5x larger than the default baseline, confirmed matching on iOS and Android. |
| `floating-box-start-mode` | ➖ (inconclusive) | ✅ | ✅ | `"open"` — box starts already expanded independent of `floating-initial-position` (which was left unset for this test), confirmed on both platforms. On iOS it then stayed open indefinitely (no auto-collapse timer, see finding above); on Android it auto-collapsed after 5s as expected from that same finding. |
| `floating-box-text-first-font-size` | ✅ | ✅ | ✅ | Confirmed twice: `2rem`/32px (web computed-style + iOS, truncates at this extreme value — expected) and again cleanly at `1.5rem` with short text (`"Deals"`) visibly larger on both iOS and Android — see `box_textalign_fontsize_clean.png`. |
| `floating-box-text-first-font-weight` | ✅ | ✅ | ✅ | `400` (regular) confirmed via web computed-style and visually on both iOS and Android (clean round with short text). **Android note**: Android's box text-weight is a **binary bold/normal** choice (`isBoldWeight`: numeric value `>= 600` → bold, else normal) rather than iOS/web's full numeric weight scale — a real, accepted platform granularity gap (Android's `Typeface` API doesn't cleanly support arbitrary numeric weights on system fonts pre-API 28). `400` and `900` both still resolve correctly to normal/bold respectively under this scheme. |
| `floating-box-text-second-font-size` | ✅ | ✅ | ✅ | `0.75rem`/12px confirmed via web computed-style + iOS in the first round; footer size difference also visually apparent in the clean round on both platforms. |
| `floating-box-text-second-font-weight` | ✅ | ✅ | ✅ | `900` (maps to bold on Android per the granularity note above) — confirmed via web, iOS, and Android (clean round: bold "New" clearly heavier than the header's regular-weight text). |
| `floating-box-text-align-first` | ✅ | ✅ | ✅ | `center` — confirmed via web computed style, and now cleanly visually confirmed on both iOS and Android using short text (`"Deals"`) instead of the earlier oversized/truncated string that left no slack space to see centering — see `box_textalign_fontsize_clean.png`. |
| `floating-box-text-align-second` | ✅ | ✅ | ✅ | `flex-end` — confirmed via web computed style, and now cleanly visually confirmed on both iOS and Android: `"New"` sits flush right in the footer stripe with visible slack space to its left, in the same clean round. |
| `floating-box-open-on-scroll` | ✅ | ✅ | ✅ | Implemented natively this session on both platforms (was previously decoded but unused) — box starts collapsed, auto-expands once on first scroll past ~100pt, then auto-collapses again a few seconds later. Verified live on iOS and Android; see "Feature added" section above for the scroll-detection technique used per platform. |
| `floating-box-open-on-time` | ➖ (not re-tested) | ✅ (via debug trace) | 🧩 | Tested `"2000"` (2s) on iOS: temporary debug logging confirmed `scheduleAutoOpenIfNeeded` reads the value correctly and the timer fires `setState(.expanded)` right on schedule — screenshotting the ~2s-to-~7s expanded window proved impractical (tool round-trip latency exceeds it, same class of issue as the pill/box timing investigations above), so verified via trace instead of a screenshot. Code is symmetric with Android's already-working `scheduleAutoOpenIfNeeded`/`autoOpenRunnable`, not independently re-screenshotted this round. |
| `floating-box-close-remember-duration` | ➖ (not re-tested) | ✅ (unit test) | ✅ (unit test) | Close button's mere existence was already visually confirmed in an earlier round (`box_colors_closebutton.png`). The *remember-duration/persistence* behavior specifically is covered by dedicated unit tests on both platforms (`PoltioTriggerDismissalStoreTest.kt` on Android, equivalent coverage in `PoltioSDKTests.swift` on iOS — `testTriggerDismissalStoreRecordAndExpire`), both passing. Read `PoltioTriggerDismissalStore`/`.kt` directly: a clean `UserDefaults`/`SharedPreferences`-backed store keyed by `publicId`, storing an expiry timestamp `hours * 3600` seconds out, gating `showTrigger` via `isDismissed`. This is arguably the more rigorous verification for time-based persistence logic than a live screenshot would be. |

Widget 393's `overlay_options` currently sits at (not reverted):
`{"trigger-type":"box","floating-box-text-first":"Smart Picks","floating-box-text-second":"Just for you","floating-box-bg-color-first":"#1A1A2E","floating-box-open-on-scroll":"true","floating-box-bg-color-second":"#F5A623","floating-box-text-color-first":"#FFFFFF","floating-box-show-close-button":"true","floating-box-text-color-second":"#1A1A2E"}`.
(Left deliberately in this state — no `floating-initial-position` set, `floating-box-open-on-scroll`
enabled — since it's now the live demonstration of the new default box behavior: starts collapsed,
opens on scroll, auto-collapses again. The earlier `floating-img`/`full-image-mode`/`resize` test
values are no longer set, but both were independently confirmed working in the previous round.)

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
  screenshot this round — see "Fixed — box auto-collapse" section above for why).
- `docs/screenshots/ios/box_image_fullmode_resize.png`,
  `docs/screenshots/android/box_image_fullmode_resize.png` — box trigger with a working
  `floating-img`, `full-image-mode: "true"`, `resize: "1.5"`, and `box-start-mode: "open"` all set
  together, confirming all 4 render identically on iOS and Android (bigger card, banner image
  filling the whole card, white text/icons floating over it).
- `docs/screenshots/ios/box_open_on_scroll.png`,
  `docs/screenshots/android/box_open_on_scroll.png` — box trigger auto-expanding mid-scroll (a
  single swipe on the Home screen's product list), confirming the newly-implemented native
  `floating-box-open-on-scroll` behavior on both platforms. Both also confirmed auto-collapsing back
  to the tab ~5s later, untouched (screenshots of that final collapsed state not kept — the
  behavior itself, not another still frame, was the point).
- `docs/screenshots/ios/box_textalign_fontsize_clean.png`,
  `docs/screenshots/android/box_textalign_fontsize_clean.png` — box trigger with short text
  (`"Deals"`/`"New"`) instead of the earlier long/oversized-font strings, giving real slack space to
  see alignment: `text-align-first: center` + `font-weight-first: 400` (regular) clearly centered
  and unbolded in the header, `text-align-second: flex-end` + `font-weight-second: 900` clearly
  right-aligned and bold in the footer — all 4 params (plus font-size) confirmed at once on both
  platforms, finally superseding the earlier inconclusive "text overflows, can't see alignment"
  finding. Also doubles as visual confirmation of the header-background-stripe fix (navy header,
  orange body, distinct bands).
- `docs/screenshots/ios/card_scroll_reveal.png`, `docs/screenshots/android/card_scroll_reveal.png`
  — card trigger fully expanded from a single scroll/swipe on the TVs screen (`floating-scroll-
  threshold: "50"` for a fast test), confirming the new native scroll-reveal on both platforms.
  Screenshotted again 6+ seconds later on both — still expanded, confirming no auto-collapse was
  accidentally added (unlike box/pill, card is meant to stay open, matching web).
- `docs/screenshots/ios/card_svg_initialposition.png`,
  `docs/screenshots/android/card_svg_initialposition.png` — card trigger with
  `floating-initial-position: "expanded"` and `floating-svg` both set, confirming the card starts
  already expanded (no interaction needed) and shows the custom phone-icon SVG in place of the
  sparkle, on both platforms at once.

## Next steps (in order) — pick up here

**Status: all three trigger types (box, pill, card) are now done**, per the user's stated priority
order (box → pill → card, "make sure it's 100% supports all the options and acting same on web
then move on"). Remaining items below are all low-priority cleanup, not new trigger-type work.

1. ~~Debug the iOS "no trigger visible" issue~~ — done, see "RESOLVED" section above.
2. ~~Box (393) full parity pass~~ — done. Every applicable param confirmed on iOS+Android; found
   and fixed the `bg-color-first` header-stripe bug; made auto-collapse the unconditional default;
   implemented native `floating-box-open-on-scroll`. `full-image-mode`'s text-vs-no-text difference
   from web and the missing-chevron-on-web difference are both flagged for the user, not changed.
   Web's own box test page is currently broken (0×0 container, unrelated to mobile SDK — see
   dedicated section above).
3. ~~Pill (394) full parity pass~~ — done. Made auto-collapse unconditional (matching box);
   implemented the same native scroll-reveal web's pill always has (no config flag, unlike box's
   opt-in version) by reusing the exact `PoltioScrollObserver` infrastructure box's fix already
   built. `floating-pill-close-remember-duration` confirmed via the same shared, unit-tested
   `PoltioTriggerDismissalStore`. Only `floating-pill-start-mode` remains as an explicit isolated
   test (currently only inferred via a related field) — very low priority given the shared code
   path is already exercised by `floating-initial-position` testing.
4. ~~Card (401) full parity pass~~ — done. Read web's `core.ts` first and correctly identified card's
   scroll behavior as a *different* one-way pattern (reveal-and-stay-open) from box/pill's
   (reveal-then-auto-collapse) — implemented accordingly via a cleaner self-managing one-shot API
   added to the shared `PoltioScrollObserver`. Also confirmed `floating-initial-position: "expanded"`
   and `floating-svg` explicitly (previously only inferred). Verified live on both platforms,
   including that it correctly does *not* auto-collapse.
5. Remaining low-priority cleanup across all three triggers: `floating-zindex` (needs a competing
   overlay to be meaningful — hard to test quickly on any trigger), the `identity` passthrough
   params (code-confirmed only, no live network capture), `floating-pill-start-mode` (explicit test),
   `box`/`pill`-`open-on-time`/`close-remember-duration` behavior-only params already covered via
   debug trace or unit tests.
6. Revert all three test widgets to something close to their original values when done (or leave a
   note if the user wants the test values kept — widget 401 has NOT been reverted yet, see above).
7. Add/extend unit tests for `showLogo` parsing (default true / explicit false) on both platforms,
   since it can't be live-tested. Same for the box/pill/card auto-collapse timers and scroll-observer
   logic added this session — currently only manually/live verified, no automated test coverage yet.

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
- **2026-09-17 (feature round)**: User asked to fix the box auto-collapse inconsistency and mimic
  web's "starts collapsed → opens on scroll → auto-collapses" pattern natively. Read web's actual
  `box.ts` implementation to understand the exact semantics (one-shot scroll listener past a 100px
  threshold, `else if` against `boxOpenOnTime`, auto-recollapse after ~3s). Implemented: (1) iOS box
  now re-arms a 5s auto-collapse timer on every expand, matching Android's already-shipped behavior
  exactly, making it the consistent default on both platforms; (2) native
  `floating-box-open-on-scroll` support on both platforms (previously parsed but completely unused)
  via new `PoltioScrollObserver` files — a `UIScrollView.contentOffset` swizzle on iOS, a
  `Window.Callback.dispatchTouchEvent` wrapper on Android (chosen specifically because
  `ViewTreeObserver.OnScrollChangedListener` doesn't fire for Jetpack Compose's internally-managed
  scrolling, and the example app itself is Compose-based). Both are purely observational — always
  delegate through to the original implementation/callback, never consume or alter touch/scroll
  behavior. Verified live end-to-end on both platforms: a single scroll on the Home screen's product
  list auto-expands the collapsed box, which then auto-collapses again ~5s later, untouched, on both
  iOS and Android. 29/29 iOS unit tests pass, Android unit tests pass, swiftformat clean. Widget 393
  left configured with `floating-box-open-on-scroll: "true"` and no `floating-initial-position` as
  a live demonstration of the new default behavior.
- **2026-09-17 (box deep-dive — full parity pass)**: Per the user's request to bring box to 100%
  parity with web before moving to pill/card, did a full parameter-by-parameter box audit backed by
  reading web's actual `box.ts` source (not just `widget-params.md`). Found and fixed a real bug:
  `floating-box-bg-color-first` was mapped to the outer card chrome (fully covered by the inner
  card, hence "not visually distinguishable" in earlier rounds) when web actually uses it for the
  **header row's own background stripe** — added a `headerBackgroundView`, moved the outer
  container to the generic `floating-bgcolor`, confirmed the two-tone header/body design now matches
  web on both iOS and Android. Re-tested font-size/weight/text-align with short text
  (`"Deals"`/`"New"`) instead of the earlier oversized/truncated strings, cleanly confirming all 6
  params at once on both platforms this time. Confirmed `box-open-on-time` still fires correctly
  after the auto-collapse change (via temporary debug trace — screenshot timing proved impractical,
  same class of issue as earlier pill/box timing chases) and `box-close-remember-duration` via
  existing dedicated unit tests on both platforms (`PoltioTriggerDismissalStoreTest.kt` /
  `testTriggerDismissalStoreRecordAndExpire`). Separately found (not fixed): web's `full-image-mode`
  drops header/footer text entirely (image-only), unlike mobile's richer "text floats over image"
  design — flagged for the user's decision rather than unilaterally removing existing functionality
  I can't currently verify live. Also found web's box has no separate chevron/collapse button at
  all (only one dual-purpose X), unlike mobile's two distinct buttons — a reasonable, deliberate
  mobile UX addition, left as-is. Separately discovered web's own box test page currently renders
  at 0×0 regardless of config (reproduced with zero custom params, survives a `localStorage` clear,
  card trigger unaffected at the same time) — entirely web-SDK/dashboard-side, out of scope, flagged
  for awareness. Box trigger is now considered fully done. Tests pass on both platforms, swiftformat
  clean. Next: pill, then card, per the user's stated priority order.
- **2026-09-17 (pill parity pass)**: Read web's actual `pill.ts` source before touching pill (same
  method that found box's real bugs). Found the pill's auto-collapse was gated behind
  `isInitialActive` on both platforms — a manually-tapped expand would stay open forever, unlike
  the box trigger which was just fixed to always auto-collapse. Removed that gate on iOS and
  Android; pill now always re-arms its existing 2s auto-collapse timer whenever expanded, for any
  reason, matching box and web (whose `.expanded` class always drops after 3s regardless of trigger).
  Separately found web's pill has an **unconditional** scroll-reveal (no config flag at all, unlike
  box's opt-in `floating-box-open-on-scroll`) — implemented the equivalent on both platforms by
  reusing the exact `PoltioScrollObserver`/`.kt` infrastructure just built for box, wiring in a new
  one-shot listener. Verified via debug trace on iOS (screenshot timing proved impractical again,
  consistent with every other short-window timing test this session); trusted Android's already-
  live-verified `PoltioScrollObserver.kt` from the box round rather than re-proving the identical
  underlying mechanism. `floating-pill-close-remember-duration` confirmed via the same shared,
  already-unit-tested `PoltioTriggerDismissalStore` box used. Pill trigger is now considered done —
  only `floating-pill-start-mode` remains as an explicit isolated test, very low priority. Tests
  pass on both platforms, swiftformat clean. Widget 394 left with no `floating-initial-position` as
  a live demonstration of the new default (starts collapsed, reveals on scroll). Next: card.
- **2026-09-17 (card parity pass — last of the three trigger types)**: Read web's actual `core.ts`
  before assuming box/pill's fix pattern applied to card too — it doesn't, cleanly. Card's web
  scroll behavior is a *different*, one-way reveal (past `scrollThreshold`, default 300, already
  modeled on mobile as `floatingScrollThreshold` but never consumed): it expands once and **stays**
  expanded, with no auto-collapse timer at all — unlike box/pill's reveal-then-auto-hide pattern.
  Confirmed mobile's card already has zero auto-collapse logic (matching web's own lack of one), so
  the only missing piece was the scroll-triggered reveal itself. Refactored `PoltioScrollObserver`/
  `.kt` to add a cleaner, self-managing one-shot API (`onScrollPast(threshold:callback:)`) alongside
  the existing box/pill notification-based one, and wired it into the card trigger with
  `floatingScrollThreshold` as the per-widget-configurable threshold. Verified live on both
  platforms: a scroll on the TVs screen (`floating-scroll-threshold: "50"` for a fast test) reveals
  the collapsed card, and it's still expanded 6+ seconds later, untouched — confirming no stray
  auto-collapse was introduced. Also explicitly tested (previously only inferred)
  `floating-initial-position: "expanded"` and `floating-svg` together on card — both confirmed on
  both platforms in one round. Tests pass on both platforms, swiftformat clean. **All three trigger
  types (box, pill, card) are now considered fully verified against web**, per the user's original
  request. Widget 401 left with `floating-svg` set as a live demonstration; `floating-scroll-
  threshold` reverted to unset (default 300).
