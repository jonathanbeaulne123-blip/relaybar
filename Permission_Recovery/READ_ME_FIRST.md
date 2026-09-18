# RelayBar 0.9.1 — Accessibility recovery

Use this only when installed **RelayBar 0.9.1 build 17** reports `Accessibility: not granted` even though macOS Settings shows RelayBar enabled.

The exact same helper is also provided at the package root as **`Fix_Access.command`**. It does not rebuild or re-sign RelayBar. After explicit `RESET` confirmation it resets only Accessibility for bundle ID `local.relaybar`, then asks you to re-add the exact `~/Applications/RelayBar.app` copy. macOS still requires your approval.

Do not repeat the reset if the in-app report already says `Accessibility: granted`.
