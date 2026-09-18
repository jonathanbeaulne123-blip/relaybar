# Primary implementation references — checked September 17, 2026

These documents establish API mechanisms, not proof that this particular implementation works on a Mac or in the user's workbook. No user source was copied from public examples.

- Google custom menus and assigned images/drawings: https://developers.google.com/apps-script/guides/menus
- Drawing.getOnAction(): https://developers.google.com/apps-script/reference/spreadsheet/drawing
- OverGridImage.getScript()/alt-text: https://developers.google.com/apps-script/reference/spreadsheet/over-grid-image
- Menu construction API (no documented inventory read method): https://developers.google.com/apps-script/reference/base/menu
- Bound editor UI context: https://developers.google.com/apps-script/reference/base/ui
- HTML-service asynchronous server calls: https://developers.google.com/apps-script/guides/html/reference/run
- Browser native messaging, host registration and framing: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Isolated content-script execution and iframe injection: https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts
- Browser tab APIs: https://developer.chrome.com/docs/extensions/reference/api/tabs

RelayBar's original Objective-C private overlay bridge remains unchanged and experimentally supported. Public browser/Google documentation does not validate that private macOS bridge. The supplied adapters for Edge, Brave and Chromium have not been run in those browsers here.
