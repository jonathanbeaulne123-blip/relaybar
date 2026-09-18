# Source notes — RelayBar 0.2.1

Retrieved September 17, 2026. Public documentation does not validate the unchanged
private modal Touch Bar adapter; that still needs on-device testing.

- Actual foundation: RelayBar_v0.2_Screenshot_Shelf.zip recovered from the user's Library.
  SHA-256 and preserved-file evidence are in PROVENANCE_0.2.1.json.
- Apple: Take a screenshot on Mac.
  https://support.apple.com/en-ca/102646
  Describes file saving after the floating thumbnail, the Screenshot Options menu,
  screenshot save locations and explicit clipboard-only captures. RelayBar does not
  alter those settings.
- Apple API reference endpoints reviewed (web tool returned JavaScript-only shells;
  the Markdown links could not be fetched by that tool, so no behavioral claims about
  these APIs are inferred from the shells):
  https://developer.apple.com/documentation/appkit/nstouchbar/defaultitemidentifiers
  https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification

Implementation reasoning comes from the actual original code: it selected the shelf
page on didAdd, while RBBridge.presentOverlay returned early for an identical bar
object. A stale/displaced visible bar is a plausible failure path, not an observed or
confirmed diagnosis of this user's Mac. The patch forces event-based re-presentation
and finite guarded recovery without changing the private bridge implementation.
