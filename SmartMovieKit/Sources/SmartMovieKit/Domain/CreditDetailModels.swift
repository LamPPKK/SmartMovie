import Foundation

public struct CreditDetail: Codable, Hashable, Sendable {
    public let creditId: String
    public let creditType: String?
    public let department: String?
    public let job: String?
    public let character: String?
    public let personSummary: PersonSummary?
    public let titleSummary: TitleSummary?

    public func applyingAdultVisibility(includeAdult: Bool) -> CreditDetail {
        CreditDetail(
            creditId: creditId,
            creditType: creditType,
            department: department,
            job: job,
            character: character,
            personSummary: personSummary,
            titleSummary: titleSummary.flatMap { includeAdult || !$0.isAdult ? $0 : nil }
        )
    }
}

public extension Credit {
    var roleName: String? { character ?? job ?? department }
}
