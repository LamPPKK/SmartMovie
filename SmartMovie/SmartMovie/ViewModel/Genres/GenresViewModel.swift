//
//  GenresViewModel.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

class GenresViewModel {
    private let apiService = APIConnection()
    private(set) var listGenres: [Genres] = [] {
        didSet {
            self.reloadCollectionViewClosure?()
        }
    }
    
    var reloadCollectionViewClosure: (() -> Void)?
    
    func fetchGenres() {
        let genresURL = "api.themoviedb.org/3/genre/movie/list?api_key=d5b97a6fad46348136d87b78895a0c06&language=en-US"
        apiService.fetchAPIFromURL(genresURL) { [weak self] body, error in
            guard let self = self else { return }
            if let error = error {
                print(error)
                return
            }
            if let body = body {
                self.convertData(body)
            }
        }
    }
    
    private func convertData(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        do {
            let result = try decoder.decode(GenreList.self, from: responseData)
            self.listGenres = result.genres ?? []
        } catch {
            print("Failed to decode JSON \(error)")
        }
    }
}

