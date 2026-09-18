# RelayBar 0.9 — permission continuity note

RelayBar is still compiled locally and ad-hoc signed by `Scripts/build.sh`. Accessibility approval may therefore fail to carry across rebuilt versions even with the same bundle ID. Runtime trust still comes from Apple's Accessibility trust API; RelayBar does not infer permission from the visible Settings switch.

`Repair_Permission.command` is byte-identical to the package-root `Fix_Access.command` in this release and targets exactly 0.9.1 build 17. It performs no rebuild, re-sign, global TCC reset or permission grant.
