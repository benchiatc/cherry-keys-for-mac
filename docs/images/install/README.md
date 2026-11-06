# Installation screenshot notes

Captured on 2026-11-06 using macOS 27.0.1. These PNGs are used by the README and the offline HTML guide packaged with the DMG. They are screenshots with guide headings, numbered outlines, cropping and opaque redactions; UI controls were not painted into the screenshots. PNGs were re-encoded and stripped of PNG text/EXIF ancillary metadata.

- `01-download.png`: the published GitHub v0.4.5 asset list, explicitly labelled as an example. The v0.4.6 candidate was unpublished during capture.
- `02-copy-app.png`: the actual v0.4.6 candidate's mounted DMG in Finder. The arrow illustrates the copy operation; the running installed app was not replaced.
- `03-open-app.png` and `08-reopen.png`: Finder with the installed Applications copy selected. The lower sidebar containing the local account was cropped out.
- `04-first-open.png`: the actual Privacy & Security page, scrolled to Security. There was no pending blocked-app message, so the caption explicitly says that Open Anyway is absent. No exception or system security setting was changed for capture.
- `05-first-run.png` and `09-helper-button.png`: the app's SwiftUI first-run view, reproduced in a disposable documentation preview with a sample profile and unapproved status. System-changing setup methods were disabled in that preview, and it did not capture or send input, load the user's profile or reset permissions. The app and caption explicitly identify these pictures as previews, rather than evidence of a clean-machine installation.
- `06-accessibility.png` and `07-input-monitoring.png`: the actual macOS permission pages with the existing Cherry Keys switch on. Unrelated app rows were hidden. On this Mac, the app's Accessibility destination is labelled Device Control and Data Access; the guide also gives the older Accessibility name.
- `09-helper-approval.png`: the actual background activity list showing Cherry Keys enabled. Other entries were hidden. This differs from the optional Open at Login list.
- `10-enable.png` and `11-ready.png`: the actual installed local build 17, paused briefly for the Enable button screenshot and then restored to active capture. The guide shows example assignments; a new installation may have an empty list.

The source screenshots, local account information, authentication prompt and disposable preview executable stay outside the public-source allowlist. No password, Apple Account, device serial, Bluetooth address or private profile export is included. The screenshots illustrate one Mac; other macOS versions, managed-device policies and first-install prompts can differ.
