//
//  SearchCell.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/5/21.
//

import UIKit

class SearchCell: UICollectionViewCell {
    private let operationQueue = OperationQueue()
    private let apiService = APIConnection()
    var dataMovieDetail: MovieDetail?
    var movieIDs: Int = 0
    
    @IBOutlet var starIMG5: UIImageView!
    @IBOutlet var starIMG4: UIImageView!
    @IBOutlet var starIMG3: UIImageView!
    @IBOutlet var starIMG2: UIImageView!
    @IBOutlet var starIMG1: UIImageView!
    @IBOutlet var movieGenres: UILabel!
    @IBOutlet var movieName: UILabel!
    @IBOutlet var moviePoster: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        fetchData(movieIDs: movieIDs)
    }

    func drawStar(scoreAverage: Float) {
        let arrStar: [UIImageView] = [starIMG1, starIMG2, starIMG3, starIMG4, starIMG5]
        for image in arrStar {
            image.image = UIImage(systemName: "star")
        }
        let numberStar = Int(scoreAverage / 2)
        if numberStar == 0 {
            return
        }
        for index in 0 ..< numberStar {
            arrStar[index].image = UIImage(systemName: "star.fill")
        }
    }
    
    func genresMove(genresMove: [Int]) {
        var text = ""
        for item in genresMove {
            text += String(item) + " | "
        }
        movieGenres.text = text
    }
    
    func showImage(idImage: Int) {
        let NSidImage = NSNumber(value: idImage)
        moviePoster.image = APIImage.share.cache.object(forKey: NSidImage)
    }
    
    func fetchData(movieIDs: Int) {
        apiService.fetchAPIFromURL("api.themoviedb.org/3/movie/\(movieIDs)?api_key=d5b97a6fad46348136d87b78895a0c06") { [weak self] body, errorMessage in
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
                var genresText = ""
                for item in self.dataMovieDetail!.genresMovie {
                    genresText += "\(item.name) | "
                }
                if !genresText.isEmpty {
                    genresText.removeLast(4)
                }
                self.movieGenres.text = genresText
            }
            
        } catch {
            print("Failed to decode JSON \(error)")
        }
    }
}
