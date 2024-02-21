//
//  MoreViewModel.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

class MoreViewModel {
    private let apiService = APIConnection()
    private(set) var listMovie: [MovieInfo] = [] {
        didSet {
            self.reloadCollectionViewClosure?()
        }
    }
    
    var reloadCollectionViewClosure: (() -> Void)?
    var idGenres: Int = 0
    var pageNum: Int = 1
    
    func fetchMovies(page: Int? = nil) {
        let currentPage = page ?? self.pageNum
        let moreURL = "https://api.themoviedb.org/3/discover/movie?api_key=d5b97a6fad46348136d87b78895a0c06&language=en-US&page=\(currentPage)&with_genres=\(idGenres)"
        
        apiService.fetchAPIFromURL(moreURL) { [weak self] body, errorMessage in
            guard let self = self else { return }
            if let errorMessage = errorMessage {
                print(errorMessage)
                return
            }
            if let body = body {
                self.convertData(body)
                if page != nil {
                    self.pageNum += 1
                }
            }
        }
    }
    
    private func convertData(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        do {
            let result = try decoder.decode(Movies.self, from: responseData)
            if self.pageNum > 1 {
                self.listMovie.append(contentsOf: result.results)
            } else {
                self.listMovie = result.results
            }
        } catch {
            print("Failed to decode JSON \(error)")
        }
    }
}
