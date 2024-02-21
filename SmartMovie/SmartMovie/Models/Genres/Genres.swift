//
//  Genres.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

struct Genres: Codable {
    var idGenres: Int
    var genresName: String
    
    enum CodingKeys: String, CodingKey {
        case idGenres = "id"
        case genresName = "name"
    }
}
