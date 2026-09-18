# Implementation references

Checked during development on 17 September 2026. These are reference sources, not dependencies downloaded by the build. No third-party Touch Bar code was vendored into RelayBar.

Apple AppKit NSTouchBar and responder integration:
https://developer.apple.com/documentation/appkit/nstouchbar
https://developer.apple.com/documentation/appkit/nsresponder/touchbar

Apple Command Line Tools installation:
https://developer.apple.com/documentation/xcode/installing-the-command-line-tools

Claude's documented desktop links — NEW chat prefill and approximate 14,000-character truncation limit:
https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link

OpenAI's current Mac app download/help page — app naming and system requirements can change. RelayBar includes an explicit app picker instead of assuming one permanent bundle identity:
https://help.openai.com/en/articles/9275200-downloading-the-chatgpt-macos-app

Existing Touch Bar implementers illustrating that cross-app/system-modal presentation uses undocumented selectors (reference only, not a compatibility guarantee):
https://github.com/Toxblh/MTMR/blob/master/MTMR/TouchBarController.swift
https://github.com/billziss-gh/EnergyBar/blob/master/src/System/NSTouchBar%2BSystemModal.m

The isolated adapter was independently implemented using Objective-C runtime checks. The presence of old selectors does not establish support or successful behavior on a current macOS release.
