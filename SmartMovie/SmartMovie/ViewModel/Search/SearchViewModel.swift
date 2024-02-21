//
//  SearchViewModel.swift
//  SmartMovie
//
//  Created by LamNDT on 22/02/2024.
//

import Foundation

//class SearchViewModel {
//    var searchResults: SearchResults? {
//        didSet {
//            self.updateSearchResultsClosure?()
//        }
//    }
//
//    var updateSearchResultsClosure: (() -> Void)?
//
//    func fetchSearchResults(for movieSearch: String) {
//        let formattedQuery = movieSearch.replacingOccurrences(of: " ", with: "%20")
//        let urlString = "https://api.themoviedb.org/3/search/movie?api_key=d5b97a6fad46348136d87b78895a0c06&query=\(formattedQuery)"
//
//        APIConnection().fetchAPIFromURL(urlString) { [weak self] (data, errorMessage) in
//            guard let self = self else { return }
//            self.parseSearchResults(data: data)
//        }
//    }
//
//    private func parseSearchResults(data: Data?) {
//        guard let data = data else { return }
//        let decoder = JSONDecoder()
//        do {
//            let results = try decoder.decode(SearchResults.self, from: data)
//            DispatchQueue.main.async {
//                self.searchResults = results
//            }
//        } catch {
//            print("Failed to decode JSON \(error)")
//        }
//    }
//}
