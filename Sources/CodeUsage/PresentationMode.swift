import Foundation

enum UsagePresentationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case brief
    case moderate
    case full

    var id: String { rawValue }

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .moderate
    }

    var localizedTitle: String {
        switch self {
        case .brief: return L10n.text("简略")
        case .moderate: return L10n.text("中度")
        case .full: return L10n.text("完整")
        }
    }
}
