# RelayBar 0.9 — Mac acceptance checklist

Use this after installing the final package on the real Mac.

1. Quit the previous RelayBar and run `Install.command`.
2. Confirm `~/Applications/RelayBar.app` reports 0.9.0 build 16.
3. Confirm RelayBar appears on the Touch Bar without manually re-enabling the old cross-app switch.
4. Confirm the right edge is Chrome · Claude · ChatGPT ·  and the contextual family controls occupy the left region.
5. Tap Chrome while it is closed: Chrome should launch/activate once. Repeat while already running: it should activate without opening a duplicate app.
6. Repeat for Claude and ChatGPT. Missing-app behavior should be disabled, not a silent tap.
7. Open the known Google Sheet: RelayBar should enter Sheet controls. Open Hearth Tools and execute one harmless tool through the already-working Verified Click path.
8. Take a screenshot: the newest-five shelf should replace the contextual region while the four fixed right-side shell buttons remain.
9. Tap : RelayBar should disappear and the normal macOS Touch Bar should own the strip. Switch between apps; RelayBar should not reclaim it.
10. Choose RB → Return RelayBar Touch Bar: the persistent shell should return.
11. Toggle RB → Pause Persistent Touch Bar twice and verify pause/resume.
12. Confirm RB → Launch RelayBar at Login is on; logout/login only when convenient and verify RelayBar starts without an extra installer/setup flow.
13. If Accessibility becomes `not granted` after the rebuild, run `Fix_Access.command`, re-approve `~/Applications/RelayBar.app`, then repeat the Sheet test.
