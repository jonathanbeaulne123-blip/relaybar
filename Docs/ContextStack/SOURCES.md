# API and convention references

Checked September 17, 2026. Implemented against the existing project's macOS 12 minimum and Swift 5 build mode; no recently added SDK-only API is required by the feature.

- Apple NSPasteboard: https://developer.apple.com/documentation/appkit/nspasteboard
- Apple changeCount: https://developer.apple.com/documentation/appkit/nspasteboard/changecount
- Apple NSPasteboardItem: https://developer.apple.com/documentation/appkit/nspasteboarditem
- Apple pasteboard access behavior / OS permission model: https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum
- Clipboard marker conventions, including private, transient, generated, source and remote clipboard markers: https://nspasteboard.org/

Apple's documentation retrieval exposed JavaScript shells for some pages; search snippets exposed the access-behavior description. Marker definitions were available as full text. The code does not assume that permission is always granted, invoke an accessBehavior selector unavailable to an older SDK, bypass consent, or change privacy defaults. Mac permission behavior remains an explicit untested acceptance item.
