//
//  MovieInfo.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

struct MovieInfo: Codable {
    let backdropPath: String?
    var genresMovis: [Genres]?
    var posterPath: String?
    var genresMovie: [Int]
    var movieName: String?
    let voteAverage: Float
    let movieID: Int
    var releaseTime: String?
    var overView: String
    var isDownload: Bool = false
    var isStar: Bool = false
    var rumtime: Int?
    
    enum CodingKeys: String, CodingKey {
        case backdropPath = "backdrop_path"
        case genresMovis = "genres"
        case posterPath = "poster_path"
        case movieName = "original_title"
        case voteAverage = "vote_average"
        case genresMovie = "genre_ids"
        case overView = "overview"
        case movieID = "id"
        case releaseTime = "release_date"
    }
}
