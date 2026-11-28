# Contributing

Build and run Ripcord as in the README's [Build from source](README.md#build-from-source). Before a
pull request, `swift test` and `swift format lint -r Sources Tests` should both pass.

Run `scripts/create-signing-certificate.sh` once, so Accessibility stays granted across
rebuilds instead of being granted again after each one (see
[Permissions](docs/permissions.md)). Its private key stays in your keychain; never commit it.

A new feature gets one row in the README's table, in both `README.md` and `README.ja.md`: an icon,
its name and one line. Details go on its settings page or in `docs/`, not the README.

## UI conventions

These settled after side-by-side comparisons with Raycast; new UI should follow them.

- **Sizes**: take text sizes and control sizes from `Metrics` (`Sources/Ripcord/Metrics.swift`),
  and draw a search-bar control with `.barControl(isFocused:)`, rather than writing numbers of a
  view's own. Measure a new kind against Raycast first and add it there.
- **Text fields**: put `.textInput()` on every text field in the panel (`SearchField`,
  `TextField`, `SecureField`). On the glass, SwiftUI hands the AppKit field under it a vibrant
  appearance that nothing blends, so typed text turns gray and placeholders dark.
- **Popovers and dropdowns**: give them `.presentationBackground(.regularMaterial)`. macOS 26's
  default Liquid Glass lets what's behind wash out the text, and `.thickMaterial` reads as opaque.
- **Scroll bars**: put `.thinScroller()` on every `ScrollView` and `List`. It draws a thin thumb
  while scrolling. The system's own turns thick, in its own gutter, when scroll bars are set to
  always show.
- **Nested corners**: a rounded row inside a rounded container gets the container's radius minus
  the inset between them, so the two curves run parallel.
- **Searchable lists in a dropdown**: rounded rows with a soft highlight that follows the pointer
  and ↑↓ (held keys repeat), Return to pick, and the search field at the bottom, focused as it
  opens.

## Releasing

Releases are made on the maintainer's Mac, which holds the two keys they're signed with: the
certificate from `scripts/create-signing-certificate.sh`, and Sparkle's EdDSA key, made once with
`.build/artifacts/sparkle/Sparkle/bin/generate_keys` (after any `swift build`). Neither goes in the
repository. Back the EdDSA key up (`generate_keys -x <file>`): without it, no update can be signed
that installed copies will accept.

1. In `Resources/Info.plist`, raise `CFBundleShortVersionString`, and `CFBundleVersion` by one.
   Sparkle offers a release only when its `CFBundleVersion` is higher than the installed one.
2. Run `scripts/make-release.sh`. It builds the app, stops if it isn't signed with the
   certificate (an ad hoc build would make every update drop Accessibility), zips it with `ditto`,
   checks the zip's copy still verifies, and writes `build/release/appcast.xml` with the zip's
   EdDSA signature.
3. Publish both files: `gh release create v<version> --title "Ripcord <version>" --notes "…"
   build/release/Ripcord-<version>.zip build/release/appcast.xml`. Every release needs its
   `appcast.xml`: Ripcord reads the feed from the latest release, and without it the check fails.
