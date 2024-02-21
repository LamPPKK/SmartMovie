//
//  GenresCollectionViewCell.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/30/2021.
//

import UIKit

class GenresCollectionViewCell: UICollectionViewCell {
    @IBOutlet var imgGenres: UIImageView!
    @IBOutlet var nameGenres: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    func setupGenres(data: MovieInfo) {
        nameGenres.text = data.movieName
    }

    func showImageGenres(idImage: Int) {
        let NSidImage = NSNumber(value: idImage)
        imgGenres.image = APIImage.share.cache.object(forKey: NSidImage)
    }
}
