//
//  Favorite+CoreDataProperties.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/5/21.
//
//

import CoreData
import Foundation

public extension Favorite {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Favorite> {
        return NSFetchRequest<Favorite>(entityName: "Favorite")
    }

    @NSManaged var idMovie: Int32
    @NSManaged var isStar: Bool
}

extension Favorite: Identifiable {}
