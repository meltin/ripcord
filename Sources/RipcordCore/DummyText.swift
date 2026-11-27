import Foundation

/// Generate Dummy Text's Japanese or English filler text of an exact length, built as Raycast's
/// Japanese Lorem Ipsum Generator builds it.
public enum DummyText {
  public enum Language: String, Codable, CaseIterable, Sendable {
    case japanese = "ja"
    case english = "en"

    public var title: String {
      switch self {
      case .japanese: "Japanese"
      case .english: "English"
      }
    }
  }

  /// The most characters asked for, as Raycast's allows.
  public static let maximumLength = 10_000

  /// The command's two fields beside the search bar: the number of characters, and the language
  /// with `preferred` first, so a menu left alone picks it.
  public static func arguments(preferred: Language) -> [ScriptCommand.Argument] {
    let languages = [preferred] + Language.allCases.filter { $0 != preferred }
    return [
      ScriptCommand.Argument(type: .text, placeholder: "Number of characters", optional: true),
      ScriptCommand.Argument(
        type: .dropdown, placeholder: "Select Language", optional: true,
        data: languages.map { .init(title: $0.title, value: $0.rawValue) }),
    ]
  }

  /// The length typed in the field: 1 when it's empty or not a number, as Raycast's, and
  /// within 0…10,000.
  public static func length(from text: String) -> Int {
    guard let number = Int(text.trimmingCharacters(in: .whitespaces)) else { return 1 }
    return min(max(number, 0), maximumLength)
  }

  public static func generate(_ language: Language, length: Int) -> String {
    var random = SystemRandomNumberGenerator()
    return generate(language, length: length, using: &random)
  }

  public static func generate(
    _ language: Language, length: Int, using random: inout some RandomNumberGenerator
  ) -> String {
    switch language {
    case .japanese: japanese(length, using: &random)
    case .english: english(length, using: &random)
    }
  }

  private static func japanese(_ length: Int, using random: inout some RandomNumberGenerator)
    -> String
  {
    func pick(_ words: [String], first count: Int? = nil) -> String {
      words[Int.random(in: 0..<(count ?? words.count), using: &random)]
    }
    // Raycast's five sentence shapes: the first five particles are は が を に へ, and the first
    // five endings suit adjectives.
    func sentence() -> String {
      switch Int.random(in: 0..<5, using: &random) {
      case 0:
        pick(japaneseNouns) + pick(japaneseParticles, first: 5) + pick(japaneseVerbs)
          + pick(japaneseSentenceEndings)
      case 1:
        pick(japaneseNouns) + "は" + pick(japaneseAdjectives)
          + pick(japaneseSentenceEndings, first: 5)
      case 2:
        pick(japaneseAdverbs) + pick(japaneseVerbs) + pick(japaneseSentenceEndings)
      case 3:
        pick(japaneseNouns) + pick(japaneseParticles, first: 5) + pick(japaneseNouns)
          + pick(japaneseParticles, first: 5) + pick(japaneseVerbs)
          + pick(japaneseSentenceEndings)
      default:
        pick(japaneseAdverbs) + pick(japaneseAdjectives) + pick(japaneseNouns) + "は"
          + pick(japaneseSentenceEndings, first: 5)
      }
    }
    let punctuation = ["。", "。", "。", "。", "？", "！", "、", "、", "、"]
    let sentenceEnds: Set<Character> = ["。", "！", "？"]
    var result = ""
    while result.count < length {
      let startsSentence = result.last.map(sentenceEnds.contains) ?? true
      // After 、 a sentence goes on with a conjunction, set off by a full-width space.
      var phrase =
        (startsSentence ? sentence() : pick(japaneseConjunctions) + sentence()) + pick(punctuation)
      if !startsSentence { phrase = "　" + phrase }
      guard result.count + phrase.count <= length else {
        result += phrase.prefix(length - result.count)
        break
      }
      result += phrase
    }
    // A cut-off sentence ends with 。 rather than mid-word, once there's room for one.
    if let last = result.last, !sentenceEnds.contains(last), result.count > 5 {
      result = result.dropLast() + "。"
    }
    return result
  }

  private static func english(_ length: Int, using random: inout some RandomNumberGenerator)
    -> String
  {
    func pick(_ words: [String]) -> String {
      words[Int.random(in: 0..<words.count, using: &random)]
    }
    var result = ""
    var sentence = pick(englishStarters) + " "
    var words = 0
    while result.count < length {
      sentence += pick(englishWords)
      words += 1
      if (words > 5 && Double.random(in: 0..<1, using: &random) < 0.2) || words > 15 {
        // Raycast's means to end on . ? or ! and pause on , ; or :; its indexes pick only
        // periods, so a sentence ends with one mostly, as there.
        sentence += pick([".", ".", ".", ".", "?", "!"]) + " "
        words = 0
        guard result.count + sentence.count <= length else {
          result += sentence.prefix(length - result.count)
          break
        }
        result += sentence
        sentence = pick(englishStarters) + " "
      } else {
        sentence +=
          Double.random(in: 0..<1, using: &random) < 0.15 ? pick([",", ";", ":"]) + " " : " "
        if result.count + sentence.count > length {
          result += sentence.prefix(length - result.count)
          break
        }
      }
    }
    return String(result.prefix(length))
  }
}
