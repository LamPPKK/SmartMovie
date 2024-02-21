//
//  Movies.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

struct Movies: Codable {
    let page: Int
    let results: [MovieInfo]
}
