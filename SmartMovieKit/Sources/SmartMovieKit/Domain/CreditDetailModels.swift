import Foundation

public struct CreditDetail: Codable, Hashable, Sendable {
    public let creditId: String
    public let creditType: String?
    public let department: String?
    public let job: String?
    public let character: String?
    public let personSummary: PersonSummary?
    public let titleSummary: TitleSummary?
}

public extension Credit {
    var roleName: String? { character ?? job ?? department }
}
