import SwiftUI

/// The panel's sizes for text and controls, measured against Raycast's side by side. A view takes
/// its sizes from here rather than numbers of its own, so the same kind of control looks the same
/// in every command.
enum Metrics {
  /// The search field's text.
  static let queryFontSize: CGFloat = 18

  /// Controls in the search bar after the query: a command's argument fields and dropdowns.
  static let barFontSize: CGFloat = 16
  static let barControlHeight: CGFloat = 28
  static let barControlRadius: CGFloat = 8
  static let barControlPadding: CGFloat = 8
  /// Between the command's icon and its fields, and between the fields.
  static let barSpacing: CGFloat = 8
  /// The command's icon before its fields, a little smaller than a row's.
  static let barIconSize: CGFloat = 22
  /// A list's filter dropdown at the search bar's end (All Types, All Tags, All Categories).
  static let filterFontSize: CGFloat = 13

  /// A form's fields (Create Snippet, Add Bookmark).
  static let formFieldHeight: CGFloat = 36
  static let formFieldRadius: CGFloat = 12
  static let formFieldPadding: CGFloat = 12
}

extension View {
  /// A control in the search bar, as Raycast draws them: filled, with a ring while it has focus.
  func barControl(isFocused: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: Metrics.barControlRadius)
    return background(shape.fill(.quaternary))
      .overlay(shape.strokeBorder(Color.primary.opacity(isFocused ? 0.35 : 0), lineWidth: 1))
      .contentShape(shape)
  }
}
