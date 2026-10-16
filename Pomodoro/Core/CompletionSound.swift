import Foundation

enum CompletionSound: String, Codable, CaseIterable, Identifiable {
    case systemDefault, silent, bell, chime, softTap, digital
    var id: String { rawValue }
    var title: String {
        switch self {
        case .systemDefault: return "System Default"
        case .silent: return "Silent"
        case .bell: return "Bell"
        case .chime: return "Chime"
        case .softTap: return "Soft Tap"
        case .digital: return "Digital"
        }
    }
    var filename: String? { self == .systemDefault || self == .silent ? nil : rawValue + ".wav" }
    static var customSoundsSupported: Bool {
        #if NATIVE_INTEGRATIONS
        true
        #else
        false
        #endif
    }
}

extension Settings {
    func completionSound(for kind: TimerKind) -> CompletionSound {
        guard notificationSound else { return .silent }
        let selection = kind == .focus ? focusCompletionSound : breakCompletionSound
        return selection.filename != nil && !CompletionSound.customSoundsSupported ? .systemDefault : selection
    }
}
