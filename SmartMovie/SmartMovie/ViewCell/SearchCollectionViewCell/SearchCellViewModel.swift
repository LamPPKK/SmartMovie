//
//  SearchCellViewModel.swift
//  SmartMovie
//
//  Created by LamNDT on 22/02/2024.
//

import Foundation

class SearchCellViewModel {
    var movieName: String
    var genresText: String
    var starRating: Float
    var moviePosterURL: URL?

    init(movieDetail: MovieDetail) {
        self.movieName = movieDetail.movieName ?? "Unknown"
        self.genresText = movieDetail.genresMovie.map { $0.name }.joined(separator: " | ")
        self.starRating = movieDetail.voteAverage / 2
        self.moviePosterURL = URL(string: "https://image.tmdb.org/t/p/w500\(movieDetail.posterPath ?? "")")
    }
}
