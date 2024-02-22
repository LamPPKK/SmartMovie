//
//  SearchViewModel.swift
//  SmartMovie
//
//  Created by LamNDT on 22/02/2024.
//

import Foundation

class SearchViewModel {
    var searchResults: SearchResults? {
        didSet {
            self.updateSearchResultsClosure?()
        }
    }

    var updateSearchResultsClosure: (() -> Void)?

    func fetchSearchResults(for movieSearch: String) {
        let formattedQuery = movieSearch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.themoviedb.org/3/search/movie?api_key=d5b97a6fad46348136d87b78895a0c06&query=\(formattedQuery)"

        APIConnection().fetchAPIFromURL(urlString) { [weak self] (responseString, errorMessage) in
            guard let self = self else { return }
            guard let responseString = responseString, let responseData = responseString.data(using: .utf8) else {
                print("Error or invalid response")
                return
            }
            self.parseSearchResults(data: responseData)
        }
    }

    private func parseSearchResults(data: Data) {
        let decoder = JSONDecoder()
        do {
            let results = try decoder.decode(SearchResults.self, from: data)
            DispatchQueue.main.async {
                self.searchResults = results
            }
        } catch {
            print("Failed to decode JSON: \(error)")
        }
    }
}
