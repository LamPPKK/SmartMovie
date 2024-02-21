//
//  GenresMovies.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

struct GenresMovies: Codable {
    var id: Int
    var name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}
