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
            ImageLoader().downloadImage(imageCode: path) { [weak self] data in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.imgMovie.image = UIImage(data: data)
                }
            }
        }
    }
    
    func overView(data: MovieInfo) {
        nameLBL.text = data.overView
    }
}

class ImageLoader {
    func downloadImage(imageCode: String, completion: @escaping (Data) -> Void) {
        guard let imageURL = URL(string: "https://image.tmdb.org/t/p/w780" + imageCode) else {
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            guard let data = data, error == nil else {
                return
            }
            completion(data)
        }.resume()
    }
}
