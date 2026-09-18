# Technical references checked September 17, 2026

The application uses the operating-system API, not any ChatGPT connector at runtime.

- Apple: [Allow accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac). Permission is an explicit user grant and can be revoked.
- Apple: [AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction). Requests an exposed action; not a Google Apps Script completion receipt.
- Apple: [AXUIElementCreateApplication](https://developer.apple.com/documentation/applicationservices/1459374-axuielementcreateapplication?language=objc). Process-scoped accessibility object.
- Apple: [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout). Bounds individual accessibility messaging calls.
- Apple: [AXUIElementIsAttributeSettable](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable?language=objc). Defensive check before requesting a browser-specific runtime accessibility flag.
- Chromium: [Accessibility technical documentation](https://www.chromium.org/developers/design-documents/accessibility/). Browser/platform accessibility architecture, not a guarantee about a particular Sheet's controls.
- Google: [Use Google Sheets with a screen reader](https://support.google.com/docs/answer/1632199?hl=en). Sheets menu-access background; not evidence that this implementation has passed live tests.

Optional AXManualAccessibility/AXEnhancedUserInterface handling is browser-specific and may be absent or behave differently between versions. Compatibility checks are runtime checks, not certified results. The original cross-app Touch Bar bridge uses undocumented interfaces and remains opt-in. No browser extension is needed for the code path shipped here.
