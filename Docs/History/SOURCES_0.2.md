# Primary references consulted — September 17, 2026

The implementation was extended from the supplied local source archive. The following Apple references informed the native adapters; they are not proof of on-device execution.

- Apple Support, Take a screenshot on Mac: https://support.apple.com/en-ca/102646 — normal capture shortcuts, Save to location, floating thumbnail, clipboard-only captures and current PNG/HEIF options.
- Apple, DispatchSource file-system event source: https://developer.apple.com/documentation/dispatch/dispatchsource/makefilesystemobjectsource(filedescriptor:eventmask:queue:)
- Apple, DispatchSource.FileSystemEvent: https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemevent
- Apple, NSPasteboardItem.setData(_:forType:): https://developer.apple.com/documentation/appkit/nspasteboarditem/setdata(_:fortype:)
- Apple, NSButton.imageScaling: https://developer.apple.com/documentation/appkit/nsbutton/imagescaling
- Apple, CGImageSourceCreateThumbnailAtIndex: https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)

Some Apple pages expose API details through their linked Markdown representation. Runtime compatibility still needs the Mac build and tests. The screenshot metadata attribute/name fallbacks are defensive implementation heuristics, not a claim that Apple guarantees an event for every capture.
