//
//  DetailViewModel.swift
//  SmartMovie
//
//  Created by LamNDT on 22/02/2024.
//

import Foundation

class DetailViewModel {
    var movieDetail: MovieDetail? {
        didSet { onDetailUpdated?() }
    }
    var listCast: [Cast] = [] {
        didSet { onCastUpdated?() }
    }
    var similarMovies: [MovieInfo] = [] {
        didSet { onSimilarMoviesUpdated?() }
    }
    
    var onDetailUpdated: (() -> Void)?
    var onCastUpdated: (() -> Void)?
    var onSimilarMoviesUpdated: (() -> Void)?
    
    private let apiService = APIConnection()
    var movieID: Int
    
    init(movieID: Int) {
        self.movieID = movieID
    }
}

extension DetailViewModel {
    func fetchMovieDetail() {
        let urlString = "api.themoviedb.org/3/movie/\(movieID)?api_key=\(Constants.API_KEY)"
        
        APIConnection().fetchAPIFromURL(urlString) { [weak self] (data, errorMessage) in
            guard let data = data else {
                print(errorMessage ?? "Unknown error")
                return
            }
            
            if let movieDetail = try? JSONDecoder().decode(MovieDetail.self, from: Data(data.utf8)) {
                DispatchQueue.main.async {
                    self?.movieDetail = movieDetail
                }
            }
        }
    }
    
    func fetchCast() {
        let urlString = "api.themoviedb.org/3/movie/\(movieID)/credits?api_key=\(Constants.API_KEY)"
        
        APIConnection().fetchAPIFromURL(urlString) { [weak self] (data, errorMessage) in
            guard let data = data else {
                print(errorMessage ?? "Unknown error")
                return
            }

            if let listCast = try? JSONDecoder().decode(ListCast.self, from: Data(data.utf8)) {
                DispatchQueue.main.async {
                    self?.listCast = listCast.cast ?? []
                }
            }
        }
    }
    
    func fetchSimilarMovies() {
        let urlString = "api.themoviedb.org/3/movie/\(movieID)/similar?api_key=\(Constants.API_KEY)"
        
        APIConnection().fetchAPIFromURL(urlString) { [weak self] (data, errorMessage) in
            guard let data = data else {
                print(errorMessage ?? "Unknown error")
                return
            }
            
            // Decode data into a collection of MovieInfo
            if let movies = try? JSONDecoder().decode(Movies.self, from: Data(data.utf8)) {
                DispatchQueue.main.async {
                    self?.similarMovies = movies.results
                }
            }
        }
    }
}
