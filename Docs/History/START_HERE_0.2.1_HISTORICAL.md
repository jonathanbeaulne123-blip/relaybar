# RelayBar 0.2.1 — Automatic Screenshot Viewer

A focused source update to the actual RelayBar v0.2 Screenshot Shelf package.
This is the Touch Bar's five-image viewer, not Preview or a separate desktop window.

## The interaction

**Save a screenshot → the Touch Bar switches to the screenshot viewer → the newest image is first.**
You do not need to tap Shots or bring RelayBar to the foreground. Tap a thumbnail to
copy the full-resolution image, then press Command–V yourself. Nothing is pasted or
sent automatically. The original screenshots are untouched.

## Install

1. Finish the earlier installer first; do not start two installers simultaneously.
   Save any unfinished RelayBar text/checkpoint and quit RelayBar from the RB menu.
2. Unzip this package into its own `RelayBar_0.2.1_Auto_Open` folder. Do not merge it
   into an older source folder. Run **Install.command from this folder**.
3. A successful installation prints `Installed: .../Applications/RelayBar.app`.
   The existing application is backed up before replacement. Project briefs,
   screenshot cache, selected screenshot folder and other saved settings are kept.
4. In **RB → Screenshot Shelf**, check that **Automatically show viewer after a
   screenshot** is checked. It defaults to ON and is remembered. Select the folder
   where macOS actually saves screenshots if you have not already done so, and
   ensure collection is started.
5. Re-enable **RB → Experimental cross-app Touch Bar… → Enable for this session**.
   This existing opt-in still resets OFF each launch. Return to ChatGPT, Claude,
   or a browser supported by the original app.

The installer uses the existing local Swift/AppKit compiler and the original
compiler-compatibility workaround. This archive is source, not a precompiled or
notarized Mac app. Do not interpret the portable tests as a successful Mac build.

## Test exactly this change

While in ChatGPT with cross-app mode enabled, tap **Tools**, then take a harmless
screenshot with Shift–Command–4, saving it in the watched folder. Once the file
has finished saving and is imported, the Touch Bar should open the viewer on its
own, without moving keyboard focus or opening the desktop panel. The new image
should be first. Repeat while the viewer is already showing: the latest image
should replace the first thumbnail automatically. Tap a thumbnail and paste into
the chat composer; the selected full-resolution image should appear, unsent.

Now take another capture and immediately tap **Tools** after the viewer appears.
The short recovery callbacks must not switch you back. Tapping **×** disables
cross-app mode; later captures must not secretly re-enable it. Re-enable explicitly
for another test. Verify that all original screenshot files still exist.

`Screenshot_Test.command` runs synthetic image, watcher, pasteboard and native
Touch Bar component checks on your Mac. It does not test physical visibility or
read your actual screenshot directory/General clipboard. `Test.command` runs the
portable engine tests using the preserved compiler workaround.

## Important limits

- Automatic collection is still file-based. macOS must first save a complete image
  into the folder you selected. The floating thumbnail/editor can delay that save.
  For less delay, use Shift–Command–5 → Options and turn off Show Floating Thumbnail.
  RelayBar does not change this macOS setting for you.
- Clipboard-only screenshots are not watched. **Add clipboard image** remains an
  explicit action. There is no background clipboard history or screen recording.
- Cross-app scope is unchanged: the configured assistants and the original
  supported browser allowlist, not every Mac app. A screenshot collected in another
  app is queued for viewer presentation when you return to a supported app. RelayBar
  never activates that other app for you.
- It uses the existing opt-in, undocumented modal Touch Bar adapter. Physical
  behavior must be checked on your macOS version. No claim of hardware verification
  is made by this package.

## What changed

A successful image import requests a real reopen, rather than merely changing the
selected page. Structural changes get a fresh native Touch Bar and retire stale
thumbnail controls; copy checkmarks update in place. Three brief recovery callbacks
cover a displaced modal bar, re-checking the frontmost app and opt-in state each
time. Tools, thumbnail taps, Hide, disabling auto-open, or a newer capture invalidate
older callbacks. There is no continuous overlay takeover timer.

The Objective-C bridge, toolchain workaround, build script, screenshot watcher,
cache and clipboard-copy engine are byte-identical to the supplied v0.2 package.

See **Docs/VALIDATION_0.2.1.md** for actual test results and untested boundaries.
Older versioned documents/receipts and the browser preview are historical.
