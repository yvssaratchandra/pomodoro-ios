import Foundation

struct SignedAppGroups: Equatable {
    let groups: [String]
    let teamID: String?

    func group(for configured: String) throws -> String {
        guard configured.hasPrefix("group."), !configured.contains("$"), configured.count > 6 else {
            throw SigningReadError.invalidConfiguration
        }
        if groups.contains(configured) { return configured }
        if let teamID, !teamID.isEmpty, !teamID.contains("."),
           groups.contains(configured + "." + teamID) {
            return configured + "." + teamID
        }
        throw SigningReadError.groupNotDeclared
    }

    // Read only the XML entitlements in a thin arm64 Mach-O code signature.
    static func read(from data: Data) throws -> SignedAppGroups {
        let bytes = [UInt8](data)
        func word(_ offset: Int, little: Bool = true) throws -> Int {
            guard offset >= 0, offset <= bytes.count - 4 else { throw SigningReadError.malformed }
            let indices = little ? Array((0..<4).reversed()) : Array(0..<4)
            return indices.reduce(0) { ($0 << 8) | Int(bytes[offset + $1]) }
        }
        guard bytes.count >= 32, try word(0) == 0xfeedfacf,
              try word(4) == 0x0100000c else { throw SigningReadError.unsupported }
        let commandCount = try word(16)
        let commandSize = try word(20)
        guard commandSize <= bytes.count - 32, commandCount <= commandSize / 8 else {
            throw SigningReadError.malformed
        }
        let commandEnd = 32 + commandSize
        var cursor = 32
        var signatureRange: Range<Int>?
        for _ in 0..<commandCount {
            guard cursor <= commandEnd - 8 else { throw SigningReadError.malformed }
            let command = try word(cursor)
            let size = try word(cursor + 4)
            guard size >= 8, size <= commandEnd - cursor else { throw SigningReadError.malformed }
            if command == 0x1d {
                guard size == 16, signatureRange == nil else { throw SigningReadError.malformed }
                let offset = try word(cursor + 8)
                let length = try word(cursor + 12)
                guard offset >= commandEnd, length >= 12, offset <= bytes.count,
                      length <= bytes.count - offset else { throw SigningReadError.malformed }
                signatureRange = offset..<(offset + length)
            }
            cursor += size
        }
        guard let signatureRange else { throw SigningReadError.missingSignature }
        let base = signatureRange.lowerBound
        guard try word(base, little: false) == 0xfade0cc0 else { throw SigningReadError.malformed }
        let length = try word(base + 4, little: false)
        let count = try word(base + 8, little: false)
        guard length >= 12, length <= signatureRange.count, count <= (length - 12) / 8 else {
            throw SigningReadError.malformed
        }
        var entitlementData: Data?
        for index in 0..<count {
            let slot = base + 12 + index * 8
            let type = try word(slot, little: false)
            let relativeOffset = try word(slot + 4, little: false)
            guard relativeOffset >= 12 + count * 8, relativeOffset <= length - 8 else {
                throw SigningReadError.malformed
            }
            let blob = base + relativeOffset
            let blobLength = try word(blob + 4, little: false)
            guard blobLength >= 8, blobLength <= length - relativeOffset else { throw SigningReadError.malformed }
            if type == 5 {
                guard entitlementData == nil, try word(blob, little: false) == 0xfade7171 else {
                    throw SigningReadError.malformed
                }
                entitlementData = Data(bytes[(blob + 8)..<(blob + blobLength)])
            }
        }
        guard let entitlementData else { throw SigningReadError.missingEntitlements }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let values = try? PropertyListSerialization.propertyList(from: entitlementData, options: [], format: &format),
              format == .xml, let dictionary = values as? [String: Any] else { throw SigningReadError.malformed }
        let groups = dictionary["com.apple.security.application-groups"] as? [String] ?? []
        return SignedAppGroups(groups: groups, teamID: dictionary["com.apple.developer.team-identifier"] as? String)
    }
}

enum SigningReadError: String, LocalizedError {
    case unsupported = "Unsupported executable format."
    case malformed = "Unable to read signing permissions."
    case missingSignature = "This executable has no signing permissions."
    case missingEntitlements = "This signature has no readable XML permissions."
    case invalidConfiguration = "The widget group configuration is invalid."
    case groupNotDeclared = "The widget group is missing from this installation’s signing permissions."
    var errorDescription: String? { rawValue }
}
