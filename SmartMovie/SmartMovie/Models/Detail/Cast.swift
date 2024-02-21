//
//  Cast.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

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
