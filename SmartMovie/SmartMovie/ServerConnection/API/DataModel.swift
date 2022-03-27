//
//  DataModel.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

enum MovieDetailCell {
    case cast
    case similar
}

struct SectionDetail {
    let name: String
    var similar: [MovieInfo]
    let typeCell: MovieDetailCell
}

struct SearchResults: Codable {
    var results: [MovieInfo]
}
struct Movies: Codable {
    let page: Int
    let results: [MovieInfo]
}
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
struct MovieDetailS: Codable {
    let results: [MovieDetail]
}
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
        case runtime = "runtime"
        case relate = "release_date"
        case lang = "original_language"
    }
}
struct GenresMovies: Codable {
    var id: Int
    var name: String
    enum odingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
    }
}

struct Genres: Codable {
    var idGenres: Int
    var genresName: String
    enum CodingKeys: String, CodingKey {
        case idGenres = "id"
        case genresName = "name"
    }
}
struct Genre: Codable {
    let genres: [Genres]?
}
class Cast: Codable {
    let castId: Int
    let castName: String?
    let profilePath: String?
    var isDownload: Bool = false
    enum CodingKeys: String, CodingKey {
        case castId = "id"
        case castName = "name"
        case profilePath = "profile_path"
    }
}
struct ListCast: Codable {
    let id: Int
    let cast: [Cast]?
    enum CodingKeys: String, CodingKey {
        case id
        case cast
    }
}
