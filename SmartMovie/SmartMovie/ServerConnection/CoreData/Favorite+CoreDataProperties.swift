//
//  Favorite+CoreDataProperties.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/5/21.
//
//

import Foundation
import CoreData


extension Favorite {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Favorite> {
        return NSFetchRequest<Favorite>(entityName: "Favorite")
    }
    
    @NSManaged public var idMovie: Int32
    @NSManaged public var isStar: Bool
    
}

extension Favorite : Identifiable {

}
