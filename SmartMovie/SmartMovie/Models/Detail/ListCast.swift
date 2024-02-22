//
//  ListCast.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

struct ListCast: Codable {
    let id: Int
    let cast: [Cast]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case cast
    }
}
