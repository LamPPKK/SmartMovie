//
//  MovieDetail.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

struct MovieDetail: Codable {
    let backdropPath: String?
    var posterPath: String?
    var genresMovie: [GenresMovies]
    var movieName: String?
    let voteAverage: Float
    let movieID: Int
    var overView: String
    var runtime: Int?
    var relate: String
    var lang: String
    
    enum CodingKeys: String, CodingKey {
        case backdropPath = "backdrop_path"
        case posterPath = "poster_path"
        case movieName = "original_title"
        case voteAverage = "vote_average"
        case genresMovie = "genres"
        case overView = "overview"
        case movieID = "id"
        case runtime
        case relate = "release_date"
        case lang = "original_language"
    }
}
