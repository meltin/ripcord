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

  /// Cards over the panel: the ⌘K menu, a dropdown's list, the icon picker, Set Alias… and
  /// Set Hotkey…, and Notes' actions.
  static let cardWidth: CGFloat = 340
  static let cardRadius: CGFloat = 16
  /// Between the card's edge and its rows.
  static let cardPadding: CGFloat = 6
  /// A row's text, and the search line typed into.
  static let cardFontSize: CGFloat = 13
  /// The title over the rows (Actions, Set Alias…).
  static let cardTitleFontSize: CGFloat = 12
  /// A real text field in a card (the icon picker's search, Set Alias…'s alias).
  static let cardFieldFontSize: CGFloat = 14
  static let cardRowHeight: CGFloat = 34
  /// Between rows, so a row and its gap are 36 points as Raycast's.
  static let cardRowSpacing: CGFloat = 2
  static let cardRowPadding: CGFloat = 10
  static let cardRowRadius: CGFloat = 8

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
