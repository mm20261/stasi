import Foundation

/// Sprachabhängige, bewusst kleine Regelsätze der deterministischen Nachbearbeitung.
enum PolishLocale: String, Codable, Sendable {
    case de
    case en
    case other

    init(locale: Locale) {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("de") {
            self = .de
        } else if identifier.hasPrefix("en") {
            self = .en
        } else {
            self = .other
        }
    }

    var hesitations: Set<String> {
        switch self {
        case .de: Self.deHesitations
        case .en: Self.enHesitations
        case .other: Self.emptySet
        }
    }

    var discourseFillers: [[String]] {
        switch self {
        case .de: Self.deDiscourseFillers
        case .en: Self.enDiscourseFillers
        case .other: Self.emptyPhrases
        }
    }

    var stutterExceptions: Set<String> {
        switch self {
        case .de: Self.deStutterExceptions
        case .en: Self.enStutterExceptions
        case .other: Self.emptySet
        }
    }

    var sentenceInitialProtectedFillers: Set<String> {
        switch self {
        case .de: Self.deSentenceInitialProtectedFillers
        case .en: Self.enSentenceInitialProtectedFillers
        case .other: Self.emptySet
        }
    }

    var strongMarkers: [[String]] {
        switch self {
        case .de: Self.deStrongMarkers
        case .en: Self.enStrongMarkers
        case .other: Self.emptyPhrases
        }
    }

    var weakMarkers: [[String]] {
        switch self {
        case .de: Self.deWeakMarkers
        case .en: Self.enWeakMarkers
        case .other: Self.emptyPhrases
        }
    }

    var markerModifiers: Set<String> {
        switch self {
        case .de: Self.deMarkerModifiers
        case .en: Self.enMarkerModifiers
        case .other: Self.emptySet
        }
    }

    var protectedFrameWords: Set<String> {
        switch self {
        case .de: Self.deProtectedFrameWords
        case .en: Self.enProtectedFrameWords
        case .other: Self.emptySet
        }
    }

    var numberWords: Set<String> {
        switch self {
        case .de: Self.deNumberWords
        case .en: Self.enNumberWords
        case .other: Self.emptySet
        }
    }

    var weekdays: Set<String> {
        switch self {
        case .de: Self.deWeekdays
        case .en: Self.enWeekdays
        case .other: Self.emptySet
        }
    }

    var months: Set<String> {
        switch self {
        case .de: Self.deMonths
        case .en: Self.enMonths
        case .other: Self.emptySet
        }
    }

    var subjectPronouns: Set<String> {
        switch self {
        case .de: Self.deSubjectPronouns
        case .en: Self.enSubjectPronouns
        case .other: Self.emptySet
        }
    }

    var commonVerbs: Set<String> {
        switch self {
        case .de: Self.deCommonVerbs
        case .en: Self.enCommonVerbs
        case .other: Self.emptySet
        }
    }

    private static let emptySet: Set<String> = []
    private static let emptyPhrases: [[String]] = []
    private static let deHesitations: Set<String> = ["ähm", "äh", "ähh", "öhm", "hm"]
    private static let enHesitations: Set<String> = ["um", "uh", "erm", "hm"]
    private static let deDiscourseFillers = [["also"], ["quasi"], ["sozusagen"], ["halt"]]
    private static let enDiscourseFillers = [
        ["so"], ["like"], ["you", "know"], ["basically"], ["actually"],
    ]
    private static let deStutterExceptions: Set<String> = [
        "das", "die", "der", "sie", "wie", "so", "nur", "ganz",
    ]
    private static let enStutterExceptions: Set<String> = ["had", "that", "very", "so"]
    private static let deSentenceInitialProtectedFillers: Set<String> = ["also"]
    private static let enSentenceInitialProtectedFillers: Set<String> = ["actually", "so"]
    private static let deStrongMarkers = [["nein"], ["nee"], ["quatsch"]]
    private static let enStrongMarkers = [["scratch", "that"], ["no"], ["nope"]]
    private static let deWeakMarkers = [["ich", "meine"], ["ich", "meinte"], ["korrektur"]]
    private static let enWeakMarkers = [
        ["i", "mean"], ["i", "meant"], ["correction"], ["scratch"],
    ]
    private static let deMarkerModifiers: Set<String> = ["äh", "ähm", "warte"]
    private static let enMarkerModifiers: Set<String> = ["uh", "um", "wait", "sorry"]
    private static let deProtectedFrameWords: Set<String> = [
        "nicht", "kein", "keine", "mehr", "weniger", "nur", "alle",
    ]
    private static let enProtectedFrameWords: Set<String> = [
        "not", "no", "more", "less", "only", "all", "never",
    ]
    private static let deNumberWords: Set<String> = [
        "null", "ein", "eins", "eine", "einen", "zwei", "drei", "vier", "fünf",
        "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf", "dreizehn",
        "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn",
        "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig",
        "neunzig", "hundert", "tausend",
    ]
    private static let enNumberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
    ]
    private static let deWeekdays: Set<String> = [
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag",
    ]
    private static let enWeekdays: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
    private static let deMonths: Set<String> = [
        "januar", "februar", "märz", "april", "mai", "juni", "juli", "august",
        "september", "oktober", "november", "dezember",
    ]
    private static let enMonths: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
    ]
    private static let deSubjectPronouns: Set<String> = ["ich", "du", "er", "sie", "es", "wir", "ihr"]
    private static let enSubjectPronouns: Set<String> = ["i", "you", "he", "she", "it", "we", "they"]
    private static let deCommonVerbs: Set<String> = [
        "bin", "bist", "ist", "sind", "seid", "habe", "hast", "hat", "haben", "habt",
        "werde", "wirst", "wird", "werden", "werdet", "brauche", "brauchst", "braucht",
        "brauchen", "muss", "musst", "müssen", "kann", "kannst", "können", "soll",
        "sollen", "will", "wollen", "möchte", "möchten", "gehe", "gehst", "geht",
        "gehen", "komme", "kommst", "kommt", "kommen", "mache", "machst", "macht",
        "machen", "nehme", "nimmst", "nimmt", "nehmen", "treffe", "triffst", "trifft",
        "treffen",
    ]
    private static let enCommonVerbs: Set<String> = [
        "am", "is", "are", "was", "were", "have", "has", "had", "do", "does", "did",
        "need", "needs", "want", "wants", "can", "could", "will", "would", "should",
        "must", "meet", "meets", "go", "goes", "come", "comes", "make", "makes",
    ]
}
