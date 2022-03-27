//
//  OneCollectionViewCell.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class OneCollectionViewCell: UICollectionViewCell {

    private let operationQueue = OperationQueue()
    private let apiService = APIConnection()
    var dataMovieDetail: MovieDetail?
    var movieIDs: Int = 0
    
    @IBOutlet weak var starIMG: UIButton!
    @IBOutlet weak var imgCell1: UIImageView!
    @IBOutlet weak var nameCell1: UILabel!
    @IBOutlet weak var timeCell1: UILabel!
    @IBOutlet weak var likeCell1: UIButton!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    func setupCell(data: MovieInfo) {
        nameCell1.text = data.movieName
        movieIDs = data.movieID
        fetchData(movieIDs: movieIDs)
    }
    
//    override func prepareForReuse() {
//        super.prepareForReuse()
//        starIMG.setImage(#imageLiteral(resourceName: "starEmpty"), for: .normal)
//    }
    
    @IBAction func funcsetStar(_ sender: Any) {
        if DBManager.shared.getfavorite(idMovie: movieIDs) == nil {
            DBManager.shared.addStar(idMovie: movieIDs, isStar: true)
            starIMG.setImage(#imageLiteral(resourceName: "starFull"), for: .normal)
        } else {
            DBManager.shared.deleteFavorite(idMovie: movieIDs)
            starIMG.setImage(#imageLiteral(resourceName: "starEmpty"), for: .normal)
        }
    }
    
    func showImageCell1(idImage: Int) {
        let NSidImage = NSNumber(value: idImage)
        imgCell1.image = APIImage.share.cache.object(forKey: NSidImage)
    }
    
    func showTime(runtime: Int?){
        guard let runtime = runtime else {
            return
        }
        timeCell1.text = "\(runtime)"

    }
    func timeMovieString(_ time: Int) -> String {
        var result = ""
        let hours = Int(time / 60)
        let minutes = time - (hours * 60)
        let minuteStr = String(format: "%02d", minutes)
        if hours > 0 {
            result = "\(hours)h \(minuteStr)mins"
        } else {
            result = "\(minutes)mins"
        }
        return result
    }
    
    func fetchData(movieIDs: Int) {
        apiService.fetchAPIFromURL("api.themoviedb.org/3/movie/\(movieIDs)?api_key=d5b97a6fad46348136d87b78895a0c06") { [weak self] (body, errorMessage) in
            guard let self = self else {
                return
            }
            if let errorMessage = errorMessage {
                print(errorMessage)
                return
            }
            if let body = body {
                self.convertData(body)
            }
        }
    }
    private func convertData(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        do {
            dataMovieDetail = try decoder.decode(MovieDetail.self, from: responseData)
            DispatchQueue.main.async {
                self.timeCell1.text = self.timeMovieString(self.dataMovieDetail?.runtime ?? 0)
            }
            
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
}
