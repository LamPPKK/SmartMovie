import Foundation

public struct AlternativeTitle: Codable, Hashable, Identifiable, Sendable {
    public let countryCode: String?
    public let title: String
    public let type: String?

    public var id: String { "\(countryCode ?? ""):\(type ?? ""):\(title)" }

    private enum CodingKeys: String, CodingKey {
        case countryCode = "iso31661"
        case title
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
    }
}

public struct ReleaseEvent: Codable, Hashable, Sendable {
    public let certification: String
    public let descriptors: [String]
    public let languageCode: String?
    public let note: String?
    public let releaseDate: String?
    public let type: Int?

    private enum CodingKeys: String, CodingKey {
        case certification
        case descriptors
        case languageCode = "iso6391"
        case note
        case releaseDate
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        certification = try container.decodeIfPresent(String.self, forKey: .certification) ?? ""
        descriptors = try container.decodeIfPresent([String].self, forKey: .descriptors) ?? []
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        type = try container.decodeIfPresent(Int.self, forKey: .type)
    }
}

public struct ReleaseInformation: Codable, Hashable, Identifiable, Sendable {
    public let countryCode: String
    public let releaseDates: [ReleaseEvent]
    public let rating: String?
    public let descriptors: [String]

    public var id: String { countryCode }
    public var certification: String? {
        rating?.nilIfEmpty ?? releaseDates.lazy.compactMap { $0.certification.nilIfEmpty }.first
    }
    public var firstReleaseDate: String? {
        releaseDates.compactMap(\.releaseDate).min()
    }

    private enum CodingKeys: String, CodingKey {
        case countryCode = "iso31661"
        case releaseDates
        case rating
        case descriptors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? ""
        releaseDates = try container.decodeIfPresent([ReleaseEvent].self, forKey: .releaseDates) ?? []
        rating = try container.decodeIfPresent(String.self, forKey: .rating)
        descriptors = try container.decodeIfPresent([String].self, forKey: .descriptors) ?? []
    }
}

public struct TitleTranslationData: Codable, Hashable, Sendable {
    public let title: String?
    public let name: String?
    public let overview: String?
    public let homepage: String?
    public let tagline: String?
    public let runtime: Int?
}

public struct TitleTranslation: Codable, Hashable, Identifiable, Sendable {
    public let languageCode: String
    public let countryCode: String
    public let languageName: String
    public let englishName: String
    public let data: TitleTranslationData

    public var id: String { "\(languageCode)-\(countryCode)" }
    public var localizedTitle: String? { data.title?.nilIfEmpty ?? data.name?.nilIfEmpty }

    private enum CodingKeys: String, CodingKey {
        case languageCode = "iso6391"
        case countryCode = "iso31661"
        case languageName = "name"
        case englishName
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode) ?? ""
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? ""
        languageName = try container.decodeIfPresent(String.self, forKey: .languageName) ?? ""
        englishName = try container.decodeIfPresent(String.self, forKey: .englishName) ?? ""
        data = try container.decodeIfPresent(TitleTranslationData.self, forKey: .data) ?? TitleTranslationData()
    }
}

public extension TitleDetailV2 {
    func releaseInformation(for region: String?) -> ReleaseInformation? {
        let normalizedRegion = region?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return releaseInformation.first { $0.countryCode.uppercased() == normalizedRegion }
    }

    func displayAlternativeTitles(for region: String?) -> [AlternativeTitle] {
        let normalizedRegion = region?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var seen = Set<String>()
        return alternativeTitles
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                let lhsPreferred = lhs.countryCode?.uppercased() == normalizedRegion
                let rhsPreferred = rhs.countryCode?.uppercased() == normalizedRegion
                return lhsPreferred && !rhsPreferred
            }
            .filter { seen.insert($0.title.lowercased()).inserted }
    }

    func displayTranslations(for language: String?) -> [TitleTranslation] {
        let normalizedLanguage = language?
            .split(separator: "-")
            .first?
            .lowercased()
        var seen = Set<String>()
        return translations
            .filter { $0.localizedTitle != nil }
            .sorted { lhs, rhs in
                let lhsPreferred = lhs.languageCode.lowercased() == normalizedLanguage
                let rhsPreferred = rhs.languageCode.lowercased() == normalizedLanguage
                return lhsPreferred && !rhsPreferred
            }
            .filter { translation in
                guard let title = translation.localizedTitle else { return false }
                return seen.insert("\(translation.languageCode.lowercased()):\(title.lowercased())").inserted
            }
    }
}

private extension TitleTranslationData {
    init() {
        title = nil
        name = nil
        overview = nil
        homepage = nil
        tagline = nil
        runtime = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
