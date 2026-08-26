extension CatalogEntity {
    var isAdultTitle: Bool {
        if case .title(let title) = self { return title.isAdult }
        return false
    }
}
