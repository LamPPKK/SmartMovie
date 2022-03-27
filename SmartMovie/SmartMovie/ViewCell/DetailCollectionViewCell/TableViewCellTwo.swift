//
//  TableViewCellTwo.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/5/21.
//

import UIKit

class TableViewCellTwo: UITableViewCell {

    @IBOutlet weak var starIMG5: UIImageView!
    @IBOutlet weak var starIMG4: UIImageView!
    @IBOutlet weak var starIMG3: UIImageView!
    @IBOutlet weak var starIMG2: UIImageView!
    @IBOutlet weak var starIMG1: UIImageView!
    @IBOutlet weak var movieGenres: UILabel!
    @IBOutlet weak var movieName: UILabel!
    @IBOutlet weak var moviePoster: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    func drawStar(scoreAverage: Float) {
        let arrStar: [UIImageView] = [starIMG1, starIMG2, starIMG3, starIMG4, starIMG5]
        for image in arrStar {
            image.image = #imageLiteral(resourceName: "starEmpty")
        }
        let numberStar: Int = Int(scoreAverage/2)
        if numberStar == 0 {
            return
        }
        for index in 0..<numberStar {
            arrStar[index].image = #imageLiteral(resourceName: "starFull")
        }
    }
    
    func genresMove(genresMove:[Int]) {
        var text = ""
        for item in genresMove {
            text += String(item)+" | "
        }
        movieGenres.text = text
    }
    func setupCell(data: MovieInfo) {
        movieName.text = data.movieName
    }
    func showImage(idImage: Int) {
        let NSidImage = NSNumber(value: idImage)
        moviePoster.image = APIImage.share.cache.object(forKey: NSidImage)
    }
}
