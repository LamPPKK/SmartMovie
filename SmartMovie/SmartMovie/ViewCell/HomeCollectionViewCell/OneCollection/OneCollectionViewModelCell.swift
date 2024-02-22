//
//  OneCollectionViewModelCell.swift
//  SmartMovie
//
//  Created by LamNDT on 21/02/2024.
//

import Foundation

class OneCollectionViewModelCell {
    var movieName: String?
    var runtime: Int?
    var isFavorite: Bool = false
    var movieID: Int
    var imageUrl: URL?

    var didUpdate: (() -> Void)?
    
    var runtimeText: String = "Loading..."
//    {
//        return timeMovieString(runtime ?? 0)
//    }

    init(movie: MovieInfo) {
        self.movieID = movie.movieID
        self.movieName = movie.movieName
        self.runtime = movie.rumtime
        self.isFavorite = DBManager.shared.getfavorite(idMovie: movie.movieID) != nil
        if let backdropPath = movie.backdropPath {
            self.imageUrl = URL(string: "https://image.tmdb.org/t/p/w500\(backdropPath)")
        }
        fetchMovieDetail()
    }

    private func timeMovieString(_ time: Int) -> String {
        guard time > 0 else {
            return "N/A"
        }
        let hours = time / 60
        let minutes = time % 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

extension OneCollectionViewModelCell {
    func fetchMovieDetail() {
           APIConnection().fetchAPIFromURL("api.themoviedb.org/3/movie/\(movieID)?api_key=\(Constants.API_KEY)") { [weak self] body, errorMessage in
               guard let self = self else { return }
               
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
               let movieDetail = try decoder.decode(MovieDetail.self, from: responseData)
               DispatchQueue.main.async {
                   self.runtimeText = self.timeMovieString(movieDetail.runtime ?? 0)
                   self.didUpdate?()
               }
           } catch {
               print("Failed to decode JSON \(error)")
           }
       }
}
