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
        case .de: ["ähm", "äh", "ähh", "öhm", "hm"]
        case .en: ["um", "uh", "erm", "hm"]
        case .other: []
        }
    }

    var discourseFillers: [[String]] {
        switch self {
        case .de: [["also"], ["quasi"], ["sozusagen"], ["halt"]]
        case .en: [["so"], ["like"], ["you", "know"], ["basically"], ["actually"]]
        case .other: []
        }
    }

    var stutterExceptions: Set<String> {
        switch self {
        case .de: ["das", "die", "der", "sie", "wie", "so", "nur", "ganz"]
        case .en: ["had", "that", "very", "so"]
        case .other: []
        }
    }

    var sentenceInitialProtectedFillers: Set<String> {
        switch self {
        case .de: ["also"]
        case .en: ["actually", "so"]
        case .other: []
        }
    }

    var strongMarkers: [[String]] {
        switch self {
        case .de: [["nein"], ["nee"], ["quatsch"]]
        case .en: [["scratch", "that"], ["no"], ["nope"]]
        case .other: []
        }
    }

    var weakMarkers: [[String]] {
        switch self {
        case .de: [["ich", "meine"], ["ich", "meinte"], ["korrektur"]]
        case .en: [["i", "mean"], ["i", "meant"], ["correction"], ["scratch"]]
        case .other: []
        }
    }

    var markerModifiers: Set<String> {
        switch self {
        case .de: ["äh", "ähm", "warte"]
        case .en: ["uh", "um", "wait", "sorry"]
        case .other: []
        }
    }

    var protectedFrameWords: Set<String> {
        switch self {
        case .de: ["nicht", "kein", "keine", "mehr", "weniger", "nur", "alle"]
        case .en: ["not", "no", "more", "less", "only", "all", "never"]
        case .other: []
        }
    }

    var numberWords: Set<String> {
        switch self {
        case .de:
            ["null", "ein", "eins", "eine", "einen", "zwei", "drei", "vier", "fünf",
             "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf", "dreizehn",
             "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn",
             "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig",
             "neunzig", "hundert", "tausend"]
        case .en:
            ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
             "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
             "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
             "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand"]
        case .other: []
        }
    }

    var weekdays: Set<String> {
        switch self {
        case .de: ["montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag"]
        case .en: ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        case .other: []
        }
    }

    var months: Set<String> {
        switch self {
        case .de:
            ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august",
             "september", "oktober", "november", "dezember"]
        case .en:
            ["january", "february", "march", "april", "may", "june", "july", "august",
             "september", "october", "november", "december"]
        case .other: []
        }
    }

    var subjectPronouns: Set<String> {
        switch self {
        case .de: ["ich", "du", "er", "sie", "es", "wir", "ihr"]
        case .en: ["i", "you", "he", "she", "it", "we", "they"]
        case .other: []
        }
    }

    var commonVerbs: Set<String> {
        switch self {
        case .de:
            ["bin", "bist", "ist", "sind", "seid", "habe", "hast", "hat", "haben", "habt",
             "werde", "wirst", "wird", "werden", "werdet", "brauche", "brauchst", "braucht",
             "brauchen", "muss", "musst", "müssen", "kann", "kannst", "können", "soll",
             "sollen", "will", "wollen", "möchte", "möchten", "gehe", "gehst", "geht",
             "gehen", "komme", "kommst", "kommt", "kommen", "mache", "machst", "macht",
             "machen", "nehme", "nimmst", "nimmt", "nehmen", "treffe", "triffst", "trifft",
             "treffen"]
        case .en:
            ["am", "is", "are", "was", "were", "have", "has", "had", "do", "does", "did",
             "need", "needs", "want", "wants", "can", "could", "will", "would", "should",
             "must", "meet", "meets", "go", "goes", "come", "comes", "make", "makes"]
        case .other: []
        }
    }
}
