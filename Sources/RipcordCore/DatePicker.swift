import Foundation

/// Pick Date's settings: how a day is written, what Return does, and how days are joined.
public struct DatePickerSettings: Codable, Equatable, Sendable {
  public static let defaultFormat = "yyyy/MM/dd(E)"
  /// The patterns Settings offers by name; any other is a custom one.
  public static let presets = [
    "yyyy/MM/dd(E)", "yyyy/MM/dd", "yyyy-MM-dd", "M月d日(E)", "yyyy年M月d日",
  ]

  /// A DateFormatter pattern, as `yyyy/MM/dd(E)`.
  public var format: String
  public var primaryAction: ClipboardSettings.PrimaryAction
  /// Between the days picked with ⌘-click.
  public var separator: String
  /// Between a range's first and last day.
  public var rangeSeparator: String
  /// A space either side of `rangeSeparator`.
  public var spacesAroundRange: Bool

  public init(
    format: String = defaultFormat, primaryAction: ClipboardSettings.PrimaryAction = .paste,
    separator: String = ", ", rangeSeparator: String = "〜", spacesAroundRange: Bool = false
  ) {
    self.format = format
    self.primaryAction = primaryAction
    self.separator = separator
    self.rangeSeparator = rangeSeparator
    self.spacesAroundRange = spacesAroundRange
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    self.init(
      format: try container.decodeIfPresent(String.self, forKey: .format) ?? defaults.format,
      primaryAction: (try? container.decodeIfPresent(
        ClipboardSettings.PrimaryAction.self, forKey: .primaryAction)) ?? defaults.primaryAction,
      separator: try container.decodeIfPresent(String.self, forKey: .separator)
        ?? defaults.separator,
      rangeSeparator: try container.decodeIfPresent(String.self, forKey: .rangeSeparator)
        ?? defaults.rangeSeparator,
      spacesAroundRange: try container.decodeIfPresent(Bool.self, forKey: .spacesAroundRange)
        ?? defaults.spacesAroundRange)
  }

  /// `day` in the format; the default one while the pattern is left empty.
  public func text(of day: Date, calendar: Calendar = .current, locale: Locale = .current)
    -> String
  {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.dateFormat =
      format.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultFormat : format
    return formatter.string(from: day)
  }

  /// What Pick Date pastes: the days earliest first, or a range's first and last day.
  public func text(for selection: DateSelection, locale: Locale = .current) -> String {
    let write = { text(of: $0, calendar: selection.calendar, locale: locale) }
    switch selection.picked {
    case .days(let days):
      return days.sorted().map(write).joined(separator: separator)
    case .range(let start, let end):
      let between = spacesAroundRange ? " \(rangeSeparator) " : rangeSeparator
      return write(min(start, end)) + between + write(max(start, end))
    }
  }
}

/// The days picked on Pick Date's calendar, and the month it shows.
public struct DateSelection: Equatable, Sendable {
  public enum Picked: Equatable, Sendable {
    /// One day, or several ⌘-clicked; never empty.
    case days([Date])
    /// From the day it started at to the day ⇧-clicked, either way round.
    case range(Date, Date)
  }

  public let calendar: Calendar
  /// The day the arrows move from, and a ⇧-click's range starts at.
  public private(set) var cursor: Date
  public private(set) var picked: Picked
  /// The first of the month the calendar shows.
  public private(set) var month: Date

  public init(day: Date = .now, calendar: Calendar = .current) {
    self.calendar = calendar
    let start = calendar.startOfDay(for: day)
    cursor = start
    picked = .days([start])
    month = calendar.dateInterval(of: .month, for: start)?.start ?? start
  }

  public func isPicked(_ day: Date) -> Bool {
    switch picked {
    case .days(let days): days.contains(day)
    case .range(let start, let end): min(start, end) <= day && day <= max(start, end)
    }
  }

  /// A click: that day alone. With ⌘ it's added or taken out; with ⇧ the range from the cursor
  /// to it.
  public mutating func click(_ day: Date, command: Bool = false, shift: Bool = false) {
    let day = calendar.startOfDay(for: day)
    if shift {
      picked = .range(cursor, day)
    } else if command {
      var days = Set(pickedDays)
      // The last one stays: there'd be nothing to paste.
      if days.contains(day) {
        guard days.count > 1 else { return }
        days.remove(day)
        // A range goes on from a day still picked.
        if cursor == day, let last = days.max() { cursor = last }
      } else {
        days.insert(day)
        cursor = day
      }
      picked = .days(days.sorted())
    } else {
      picked = .days([day])
      cursor = day
    }
    show(day)
  }

  /// The arrows: that many days on from the cursor, alone.
  public mutating func move(by days: Int) {
    guard let day = calendar.date(byAdding: .day, value: days, to: cursor) else { return }
    click(day)
  }

  /// The header's arrows: the month before or after, leaving what's picked.
  public mutating func showMonth(by months: Int) {
    month = calendar.date(byAdding: .month, value: months, to: month) ?? month
  }

  /// Six weeks from the start of the one the month begins in, so the calendar keeps its height.
  public var grid: [Date] {
    let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    return (-lead..<(42 - lead)).compactMap {
      calendar.date(byAdding: .day, value: $0, to: month)
    }
  }

  private var pickedDays: [Date] {
    switch picked {
    case .days(let days): return days
    case .range(let start, let end):
      // shortcut: lists every day of the range; fine for months, slow for a range of decades.
      return stride(from: 0, through: daysBetween(min(start, end), max(start, end)), by: 1)
        .compactMap { calendar.date(byAdding: .day, value: $0, to: min(start, end)) }
    }
  }

  private func daysBetween(_ start: Date, _ end: Date) -> Int {
    calendar.dateComponents([.day], from: start, to: end).day ?? 0
  }

  private mutating func show(_ day: Date) {
    month = calendar.dateInterval(of: .month, for: day)?.start ?? month
  }
}

extension Search {
  /// Pick Date's one row: what Return pastes or copies, with both on ⌘K.
  public static func datePickerSections(
    _ selection: DateSelection, settings: DatePickerSettings, locale: Locale = .current
  ) -> [SearchSection] {
    let text = settings.text(for: selection, locale: locale)
    let copyFirst = settings.primaryAction == .copy
    let paste = MenuAction(
      title: "Paste to App", symbol: "return", shortcut: copyFirst ? "⌘↵" : "↵",
      action: .pasteText(text))
    let copy = MenuAction(
      title: "Copy to Clipboard", symbol: "doc.on.doc", shortcut: copyFirst ? "↵" : "⌘↵",
      action: .copy(text))
    var row = SearchResult(
      id: "date", title: text, subtitle: "", keyword: nil, kind: .text,
      action: copyFirst ? copy.action : paste.action)
    row.menu = copyFirst ? [copy, paste] : [paste, copy]
    return [SearchSection(title: "Date", results: [row])]
  }
}
