import SwiftUI

extension View {
  /// The scroll bar Ripcord uses everywhere: a thin thumb shown while scrolling, as Raycast
  /// draws its own. The system's is hidden, since with scroll bars set to always show it's the
  /// thick one in its own gutter whatever the view asks for.
  func thinScroller() -> some View { modifier(ThinScroller()) }
}

private struct ThinScroller: ViewModifier {
  @State private var geometry: ScrollGeometry?
  @State private var isScrolling = false
  @State private var hide: Task<Void, Never>?

  func body(content: Content) -> some View {
    content
      // .never, not .hidden: .hidden still draws the system's when it's set to always show.
      .scrollIndicators(.never)
      // Shown as the offset moves rather than on scroll phases, which a List never reports.
      .onScrollGeometryChange(for: ScrollGeometry.self) {
        $0
      } action: { old, new in
        geometry = new
        if old.contentOffset != new.contentOffset { showForAMoment() }
      }
      .overlay(alignment: .topTrailing) {
        ScrollThumb(geometry: geometry).opacity(isScrolling ? 1 : 0)
      }
  }

  private func showForAMoment() {
    if !isScrolling { withAnimation(.easeOut(duration: 0.15)) { isScrolling = true } }
    hide?.cancel()
    hide = Task {
      // A pause first, so it doesn't blink between flicks of the wheel.
      try? await Task.sleep(for: .seconds(0.8))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.4)) { isScrolling = false }
    }
  }
}

private struct ScrollThumb: View {
  let geometry: ScrollGeometry?

  var body: some View {
    if let geometry {
      let insets = geometry.contentInsets.top + geometry.contentInsets.bottom
      let scrollable = geometry.contentSize.height + insets - geometry.containerSize.height
      if scrollable > 1 {
        // Clear of rounded corners and the edges of what's around it.
        let margin: CGFloat = 12
        let track = geometry.containerSize.height - margin * 2
        let visible = geometry.containerSize.height / (geometry.contentSize.height + insets)
        let height = max(24, track * visible)
        let offset = geometry.contentOffset.y + geometry.contentInsets.top
        let progress = min(max(offset / scrollable, 0), 1)
        Capsule()
          .fill(Color.primary.opacity(0.25))
          .frame(width: 4, height: height)
          .offset(y: margin + (track - height) * progress)
          .padding(.trailing, 4)
          .allowsHitTesting(false)
      }
    }
  }
}
