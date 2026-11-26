# Contributing

Build and run Ripcord as in the README's [Build from source](README.md#build-from-source). Before a
pull request, `swift test` and `swift format lint -r Sources Tests` should both pass.

Run `scripts/create-signing-certificate.sh` once, so Accessibility stays granted across
rebuilds instead of being granted again after each one (see the README's
[Permissions](README.md#permissions)). Its private key stays in your keychain; never commit it.

## UI conventions

These settled after side-by-side comparisons with Raycast; new UI should follow them.

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
