//
//  StringExtensions.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation
extension String {
    func toDate(withFormat: String) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = withFormat
        dateFormatter.locale = Locale(identifier: "en_GB")
        guard let date = dateFormatter.date(from: self) else { return Date() }
        return date
    }
}
