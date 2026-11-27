import SwiftUI

/// Ripcord's sizes for text and controls, the panel's and its windows', measured against Raycast's
/// side by side. A view takes its sizes from here rather than numbers of its own, so the same kind
/// of control looks the same in every command.
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
  /// Set Hotkey…, and Notes' actions. 350, as Raycast's ⌘K card, so its longest names fit beside
  /// four keycaps.
  static let cardWidth: CGFloat = 350
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

  // Text in the panel, by what it is. Two roles at the same size stay two names, so one can
  // change without the other.
  /// A row's title.
  static let rowTitleFontSize: CGFloat = 14
  /// A row's subtitle after its title.
  static let rowSubtitleFontSize: CGFloat = 14
  /// A row's kind on the right (Command, Application).
  static let rowKindFontSize: CGFloat = 13
  /// A repository's path on the right of its row.
  static let rowPathFontSize: CGFloat = 13
  /// A snippet's keyword in its row.
  static let rowKeywordFontSize: CGFloat = 13
  /// A snippet's tags in its row.
  static let rowTagFontSize: CGFloat = 12
  /// A list's section header, and the emoji grid's.
  static let sectionFontSize: CGFloat = 12
  /// An emoji a Script Command uses as its icon.
  static let iconEmojiFontSize: CGFloat = 17
  /// An emoji in the emoji grid.
  static let emojiTileFontSize: CGFloat = 34
  /// No Results' title.
  static let emptyTitleFontSize: CGFloat = 15
  /// No Results' line under the title.
  static let emptyMessageFontSize: CGFloat = 13
  /// A message over the footer, as after a failed paste.
  static let toastFontSize: CGFloat = 13
  /// The footer's action names.
  static let footerFontSize: CGFloat = 12
  /// A key in a keycap.
  static let keycapFontSize: CGFloat = 10
  /// The ↵ drawn in a keycap.
  static let keycapGlyphFontSize: CGFloat = 9
  /// Clipboard History's and Search Snippets' preview of the text.
  static let previewFontSize: CGFloat = 12
  /// The Information heading under a preview.
  static let infoTitleFontSize: CGFloat = 12
  /// The Information rows under a preview.
  static let infoFontSize: CGFloat = 12
  /// A fullOutput Script Command's title over its output.
  static let outputTitleFontSize: CGFloat = 13
  /// A fullOutput Script Command's output.
  static let outputFontSize: CGFloat = 12
  /// The ? on an argument that can be left empty.
  static let optionalBadgeFontSize: CGFloat = 8
  /// A confirmation's title, as before Empty Trash.
  static let confirmationTitleFontSize: CGFloat = 15
  /// A confirmation's message.
  static let confirmationMessageFontSize: CGFloat = 13
  /// A confirmation's buttons.
  static let confirmationButtonFontSize: CGFloat = 13
  /// Set Hotkey…'s caption and its problem line.
  static let cardCaptionFontSize: CGFloat = 12
  /// A key held in Set Hotkey….
  static let cardKeyFontSize: CGFloat = 11
  /// Set Alias…'s and Set Hotkey…'s footer: the row and the hints.
  static let cardFooterFontSize: CGFloat = 12
  /// A form's fields, and its menus.
  static let formFontSize: CGFloat = 14
  /// Create Snippet's text box.
  static let formTextBoxFontSize: CGFloat = 13
  /// A form field's label, and the Placeholders heading.
  static let formLabelFontSize: CGFloat = 12
  /// A placeholder chip under Create Snippet's text box.
  static let placeholderChipFontSize: CGFloat = 11

  /// A form's fields (Create Snippet, Add Bookmark).
  static let formFieldHeight: CGFloat = 36
  static let formFieldRadius: CGFloat = 12
  static let formFieldPadding: CGFloat = 12

  // Text in Ripcord's other windows: Settings, the first-run window, Notes, Clean Keyboard and
  // a Script Command's message.
  /// A page in Settings' sidebar, and a search result there.
  static let settingsSidebarFontSize: CGFloat = 13
  /// A heading over pages in Settings' sidebar.
  static let settingsSidebarSectionFontSize: CGFloat = 11
  /// A Settings page's title.
  static let settingsPageTitleFontSize: CGFloat = 15
  /// A Settings page's summary under its title.
  static let settingsPageSummaryFontSize: CGFloat = 12
  /// A setting's title, and a row in a Settings list (Quicklinks, Shortcuts, apps).
  static let settingsRowFontSize: CGFloat = 13
  /// A setting's description under its title.
  static let settingsRowDescriptionFontSize: CGFloat = 12
  /// A setting's monospaced detail, as a path.
  static let settingsRowDetailFontSize: CGFloat = 12
  /// A column heading over a Settings list.
  static let settingsColumnHeadingFontSize: CGFloat = 12
  /// A Settings list's line when it's empty.
  static let settingsEmptyFontSize: CGFloat = 13
  /// A folder's path in a Settings list.
  static let settingsFolderFontSize: CGFloat = 13
  /// A Quicklink's URL field.
  static let settingsURLFontSize: CGFloat = 12
  /// The banner when config.json can't be read.
  static let settingsBannerFontSize: CGFloat = 12
  /// Ripcord's version under General.
  static let settingsVersionFontSize: CGFloat = 12
  /// A footnote in Settings, as under Permissions.
  static let settingsFootnoteFontSize: CGFloat = 11
  /// A hotkey recorder's warning.
  static let hotkeyRecorderMessageFontSize: CGFloat = 11
  /// A permission's state on the right of its row.
  static let permissionStateFontSize: CGFloat = 12
  /// An app picker's list and search.
  static let appPickerFontSize: CGFloat = 13
  /// The first-run window's title.
  static let welcomeTitleFontSize: CGFloat = 20
  /// The first-run window's text.
  static let welcomeBodyFontSize: CGFloat = 13
  /// A heading in the first-run window.
  static let welcomeHeadingFontSize: CGFloat = 13
  /// The first-run window's closing line.
  static let welcomeFootnoteFontSize: CGFloat = 12
  /// A note's title in the Notes window's bar.
  static let notesTitleFontSize: CGFloat = 13
  /// A note's problem line, as when it can't be saved.
  static let notesProblemFontSize: CGFloat = 12
  /// A note's character count.
  static let notesCountFontSize: CGFloat = 13
  /// The T that opens a note's formatting.
  static let notesFormatButtonFontSize: CGFloat = 17
  /// Notes' Moved to Trash message.
  static let notesToastFontSize: CGFloat = 13
  /// Notes' Undo.
  static let notesToastButtonFontSize: CGFloat = 13
  /// Clean Keyboard's title.
  static let cleanKeyboardTitleFontSize: CGFloat = 28
  /// Clean Keyboard's countdown.
  static let cleanKeyboardCountdownFontSize: CGFloat = 48
  /// Clean Keyboard's warning when keys get through.
  static let cleanKeyboardWarningFontSize: CGFloat = 15
  /// Clean Keyboard's line under the countdown.
  static let cleanKeyboardMessageFontSize: CGFloat = 15
  /// A silent Script Command's message on screen.
  static let scriptHUDFontSize: CGFloat = 14
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
