import Foundation

struct LiveContainerLaunchURL {
    private let components: URLComponents

    init(_ url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              !["http", "https", "file", "pomodoro", "pomodoro-native"].contains(scheme),
              components.host == "livecontainer-launch", components.path.isEmpty,
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let items = components.queryItems else {
            throw AppError.invalid("Paste the launch URL copied from Pomodoro in LiveContainer.")
        }
        for name in ["bundle-name", "container-folder-name", "jit", "open-url"] {
            guard items.filter({ $0.name == name }).count <= 1 else {
                throw AppError.invalid("This launch URL has duplicate parameters. Copy it again from LiveContainer.")
            }
        }
        guard let bundle = items.first(where: { $0.name == "bundle-name" })?.value,
              !bundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, bundle != "ui" else {
            throw AppError.invalid("Copy Pomodoro's launch URL from LiveContainer, rather than the LiveContainer app URL.")
        }
        self.components = components
    }

    var launchURL: URL { url(forwarding: nil) }

    func url(forwarding guestURL: URL?) -> URL {
        var copy = components
        var items = (copy.queryItems ?? []).filter { $0.name != "open-url" }
        if let guestURL {
            items.append(URLQueryItem(name: "open-url", value: Data(guestURL.absoluteString.utf8).base64EncodedString()))
        }
        copy.queryItems = items
        // Escape literal plus signs so URL consumers cannot treat them as spaces.
        copy.percentEncodedQuery = copy.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return copy.url!
    }
}
