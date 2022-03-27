//
//  NewCollectionViewCell.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 27/03/2022.
//

import UIKit

class NewCollectionViewCell: UICollectionViewCell {

    private let operationQueue = OperationQueue()
    private let apiService = APIConnection()
    var dataMovieDetail: MovieDetail?
    var movieIDs: Int = 0
    
    @IBOutlet weak private var rateView: UIView!
    @IBOutlet weak private var imgMovie: UIImageView!
    @IBOutlet weak private var rateLBL: UILabel!
    @IBOutlet weak private var yearLBL: UILabel!
    @IBOutlet weak private var nameLBL: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        rateView.layer.cornerRadius = rateView.frame.size.width / 2
        rateView.clipsToBounds = true
        rateView.layer.backgroundColor = #colorLiteral(red: 0.9372549057, green: 0.3490196168, blue: 0.1921568662, alpha: 1)
    }
    
    override func prepareForReuse() {
        imgMovie.image = nil
    }
    
    func setupCell(data: MovieInfo) {
        nameLBL.text = data.movieName
        yearLBL.text = data.releaseTime?.components(separatedBy: "-").first
        rateLBL.text = "\(data.voteAverage)"
        movieIDs = data.movieID
        if let path = data.posterPath {
            imgMovie.loadFrom(URLAddress: "https://image.tmdb.org/t/p/w780/\(path)")
        }
    }
    
    func overView(data: MovieInfo) {
        nameLBL.text = data.overView
    }
}
