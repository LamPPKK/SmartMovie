//
//  ViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/2/21.
//

class ViewController {
    private let apiService = APIConnection()
    var genresURL = "api.themoviedb.org/3/genre/movie/list?api_key=d5b97a6fad46348136d87b78895a0c06&language=en-US"
    var listGenres = [Genres]()
    private func fetchData(_ url: String) {
        apiService.fetchAPIFromURL(url) { [weak self] (body, error) in
            guard let self = self else {
                return
            }
            if let error = error {
                print(error)
                return
            }
            if let body = body {
                self.convertData(body)
            }
        }
    }
    private func convertData(_ data: String) {
        
    }
}
