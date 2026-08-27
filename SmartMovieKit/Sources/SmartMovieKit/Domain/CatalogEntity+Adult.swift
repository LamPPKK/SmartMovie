extension CatalogEntity {
    var isAdultTitle: Bool {
        if case .title(let title) = self { return title.isAdult }
        return false
    }

    func applyingAdultVisibility(includeAdult: Bool) -> CatalogEntity? {
        switch self {
        case .title(let title):
            return includeAdult || !title.isAdult ? self : nil
        case .person(let person):
            return .person(PersonSummary(
                id: person.id,
                name: person.name,
                profilePath: person.profilePath,
                knownForDepartment: person.knownForDepartment,
                popularity: person.popularity,
                knownFor: person.knownFor.filter { includeAdult || !$0.isAdult }
            ))
        case .season, .episode:
            return includeAdult ? self : nil
        default:
            return self
        }
    }
}

extension Array where Element == CatalogEntity {
    func applyingAdultVisibility(includeAdult: Bool) -> [CatalogEntity] {
        compactMap { $0.applyingAdultVisibility(includeAdult: includeAdult) }
    }
}

public enum CatalogAdultVisibility {
    public static func titles(_ values: [TitleSummary], includeAdult: Bool) -> [TitleSummary] {
        values.filter { includeAdult || !$0.isAdult }
    }

    public static func credits(_ values: [Credit], includeAdult: Bool) -> [Credit] {
        values.filter { includeAdult || $0.adult != true }
    }
}
