//
//  APIConnection.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

protocol APIConnectionProtocol {
    func fetchAPIFromURL(_ url: String, complitionHandler: @escaping (String?, String?) -> Void)
}

class APIConnection {
    let defaultSession = URLSession(configuration: URLSessionConfiguration.default)
    var dataTask: URLSessionDataTask?
    private let domain = "https://"
}

extension APIConnection: APIConnectionProtocol {
    func fetchAPIFromURL(_ url: String, complitionHandler: @escaping (String?, String?) -> Void) {
        guard let url = URL(string: "\(domain)\(url)") else {
            complitionHandler(nil, "URL incorrect")
            return
        }
        dataTask = defaultSession.dataTask(with: url) { data, response, error in
            if let error = error?.localizedDescription {
                complitionHandler(nil, error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                complitionHandler(nil, "HTTP status failed")
                return
            }
            guard let dataa = data else {
                return
            }
            let string = String(data: dataa, encoding: .utf8)
            complitionHandler(string, nil)
        }
        dataTask?.resume()
    }
}

class APIImage {
    static let share: APIImage = .init()
    var cache = NSCache<NSNumber, UIImage>()
    var domain: String = "https://image.tmdb.org/t/p/"
    func startDownload(url: String, imageName: String, idImage: Int, size: String) {
        let domains: String = domain + size + url
        guard let urlConvert = URL(string: domains) else { return }
        downloadImage(from: urlConvert, imageName: imageName, idImage: idImage)
    }

    private func downloadImage(from url: URL, imageName: String, idImage: Int) {
        getData(from: url) { data, _, error in
            guard let data = data, error == nil else { return }
            guard let image = UIImage(data: data) else { return }
            let NSidImage = NSNumber(value: idImage)
            self.cache.setObject(image, forKey: NSidImage)
        }
    }

    func getData(from url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        URLSession.shared.dataTask(with: url, completionHandler: completion).resume()
    }
}

class DownloadImage: Operation {
    let imageName: String
    let url: String
    let idImage: Int
    let size: String
    init(_ imageName: String, url: String, idImage: Int, size: String) {
        self.imageName = imageName
        self.url = url
        self.idImage = idImage
        self.size = size
    }

    override func main() {
        if isCancelled {
            return
        }
        APIImage.share.startDownload(url: url, imageName: imageName, idImage: idImage, size: size)
    }
}
