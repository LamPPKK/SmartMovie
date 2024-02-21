//
//  DetailViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class DetailViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var averagePoint: UILabel!
    @IBOutlet weak var starIMG5: UIImageView!
    @IBOutlet weak var starIMG4: UIImageView!
    @IBOutlet weak var starIMG3: UIImageView!
    @IBOutlet weak var starIMG2: UIImageView!
    @IBOutlet weak var starIMG1: UIImageView!
    @IBOutlet weak var movieGenres: UILabel!
    @IBOutlet weak var movieName: UILabel!
    @IBOutlet weak var moviePoster: UIImageView!
    @IBOutlet weak var overView: UILabel!
    @IBOutlet weak var releaseDate: UILabel!
    @IBOutlet weak var language: UILabel!
    @IBOutlet weak var tableView: UITableView!
    private var arrayTitle: [String] = ["Movie Cast", " Similar Movie"]
    
    var dataDetails: [SectionDetail] = [SectionDetail(name: "cast", similar: [], typeCell: .cast),
                                        SectionDetail(name: "similar", similar: [], typeCell: .similar)]
    var operationQueue = OperationQueue()
    let apiConnection = APIConnection()
    var dataMovieDetail: MovieDetail?
    var listMovie = [MovieInfo]()
    var listCast: [Cast] = []
    var movieID: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print(movieID)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UINib(nibName: "TableViewCellOne", bundle: nil), forCellReuseIdentifier: "TableViewCellOne")
        tableView.register(UINib(nibName: "TableViewCellTwo", bundle: nil), forCellReuseIdentifier: "TableViewCellTwo")
        tableView.register(TableViewCell.self, forHeaderFooterViewReuseIdentifier: "TableViewCell")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchData(movieId: movieID)
        fetchCast(movieId: movieID)
    }
    func fetchSimilar(movieSearch: String) {
        apiConnection.fetchAPIFromURL("api.themoviedb.org/3/search/movie?api_key=d5b97a6fad46348136d87b78895a0c06&query=\(movieSearch)") { [weak self] (body, errorMessage) in
            guard self != nil else {
                print("Self released")
                return
            }
            if let errorMessage = errorMessage {
                print(errorMessage)
                return
            }
            if let body = body {
                self?.convertSimilar(body)
            }
        }
    }
    private func convertSimilar(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        var result: Movies?
        do {
            result = try decoder.decode(Movies.self, from: responseData)
            if let list = result?.results {
                print(list)
                self.dataDetails[1].similar = list
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    func fetchCast(movieId: Int) {
        apiConnection.fetchAPIFromURL("api.themoviedb.org/3/movie/\(movieId)/credits?api_key=d5b97a6fad46348136d87b78895a0c06") { [weak self] (body, errorMessage) in
            guard self != nil else {
                print("Self released")
                return
            }
            if let errorMessage = errorMessage {
                print(errorMessage)
                return
            }
            if let body = body {
                self?.convertCast(body)
            }
        }
    }
    private func convertCast(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        var result: ListCast?
        do {
            result = try decoder.decode(ListCast.self, from: responseData)
            if let list = result {
                print(list)
                self.listCast = list.cast ?? []
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch dataDetails[indexPath.section].typeCell {
        case .cast:
            return 400
        case .similar:
            return 200
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "TableViewCell") as? TableViewCell else {
            return UIView()
        }
        header.configure(with: arrayTitle[section])
        return header
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        50
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if dataDetails[section].similar.isEmpty {
            return 1
        } else {
            return dataDetails[section].similar.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch dataDetails[indexPath.section].typeCell {
        case .cast:
            guard let castCell = tableView.dequeueReusableCell(withIdentifier: "TableViewCellOne") as? TableViewCellOne else {
                return UITableViewCell()
            }
            if !listCast.isEmpty {
                castCell.listCast = listCast
            }
            return castCell
        case .similar:
            guard let castCell = tableView.dequeueReusableCell(withIdentifier: "TableViewCellTwo") as? TableViewCellTwo else {
                return UITableViewCell()
            }
            if !dataDetails[1].similar.isEmpty {
                castCell.layer.cornerRadius = 10
                castCell.layer.borderWidth = 1
                castCell.layer.borderColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                castCell.drawStar(scoreAverage: dataDetails[1].similar[indexPath.row].voteAverage)
                castCell.movieName.text = dataDetails[1].similar[indexPath.row].movieName
                castCell.setupCell(data: dataDetails[1].similar[indexPath.row])
                castCell.genresMove(genresMove: dataDetails[1].similar[indexPath.row].genresMovie)
                castCell.showImage(idImage: dataDetails[1].similar[indexPath.row].movieID)
                if dataDetails[1].similar[indexPath.row].backdropPath == "" {
                    return castCell
                }
                if dataDetails[1].similar[indexPath.row].isDownload == true {
                    return castCell
                } else {
                    dataDetails[1].similar[indexPath.row].isDownload = true
                    let imageName = dataDetails[1].similar[indexPath.row].backdropPath?.replacingOccurrences(of: "/", with: "")
                    addInQeueDownload(imageName: imageName?.replacingOccurrences(of: ".jpg", with: "") ?? "" ,
                                      urlposter: dataDetails[1].similar[indexPath.row].backdropPath ?? "" ,
                                      indexPath: indexPath,
                                      idImage: dataDetails[1].similar[indexPath.row].movieID)
                }
            }
            return castCell
        }
    }
    
    func fetchData(movieId: Int) {
        apiConnection.fetchAPIFromURL("api.themoviedb.org/3/movie/\(movieId)?api_key=d5b97a6fad46348136d87b78895a0c06") { [weak self] (body, errorMessage) in
            guard self != nil else {
                print("Self released")
                return
            }
            if let errorMessage = errorMessage {
                print(errorMessage)
                return
            }
            if let body = body {
                self?.convertData(body)
                DispatchQueue.main.async { [weak self] in
                    if let dataMovieDetail = self?.dataMovieDetail {
                        let imageName = dataMovieDetail.posterPath?.replacingOccurrences(of: "/", with: "")
                        self?.addInQeueDownload(imageName: imageName?.replacingOccurrences(of: ".jpg", with: "") ?? "", urlposter: dataMovieDetail.posterPath ?? "", indexPath: [0,0], idImage: dataMovieDetail.movieID)
                        self?.navigationItem.title = dataMovieDetail.movieName
                        self?.movieName.text = dataMovieDetail.movieName
                        self?.overView.text = dataMovieDetail.overView
                        var genresText = ""
                        for item in dataMovieDetail.genresMovie {
                            genresText += "\(item.name) | "
                        }
                        if !genresText.isEmpty {
                            genresText.removeLast(4)
                        }
                        self?.movieGenres.text = genresText
                        let moreFont = UIFont(name: "Helvetica-Oblique", size: 17.0)
                        let moreFontColor = UIColor.red
                        self?.overView.addTrailing(with: "... ", moreText: "Show more", moreTextFont: moreFont!, moreTextColor: moreFontColor)
                        let readMoreGesture = UITapGestureRecognizer(target: self, action:#selector(self?.showViewMore(_:)))
                        readMoreGesture.numberOfTapsRequired = 1
                        self?.overView.addGestureRecognizer(readMoreGesture)
                        self?.overView.isUserInteractionEnabled = true
                        self?.drawStar(scoreAverage: dataMovieDetail.voteAverage)
                        self?.averagePoint.text = "\(dataMovieDetail.voteAverage) / 10"
                        self?.releaseDate.text = "Release Date: \(dataMovieDetail.relate)"
                        self?.fetchSimilar(movieSearch: dataMovieDetail.movieName ?? "a")
                        guard let self = self else {
                            return
                        }
                        self.language.text = "Language: \(dataMovieDetail.lang) -   \(self.timeMovieString(self.dataMovieDetail?.runtime ?? 0))"
                    }
                }
            }
        }
    }
    func timeMovieString(_ time: Int) -> String {
        var result = ""
        let hours = Int(time / 60)
        let minutes = time - (hours * 60)
        let minuteStr = String(format: "%02d", minutes)
        if hours > 0 {
            result = "\(hours)H \(minuteStr)M"
        } else {
            result = "\(minutes)Mins"
        }
        return result
    }
    private func convertData(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        do {
            dataMovieDetail = try decoder.decode(MovieDetail.self, from: responseData)
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    
    @objc func showViewMore(_ sender: UITapGestureRecognizer) {
        overView.numberOfLines = 10
        DispatchQueue.main.async {
            self.overView.text = self.dataMovieDetail?.overView
        }
    }
    
    func drawStar(scoreAverage: Float) {
        let arrStar: [UIImageView] = [starIMG1, starIMG2, starIMG3, starIMG4, starIMG5]
        for image in arrStar {
            image.image = UIImage(systemName: "start")
        }
        let numberStar: Int = Int(scoreAverage/2)
        if numberStar == 0 {
            return
        }
        for index in 0..<numberStar {
            arrStar[index].image = UIImage(systemName: "star.fill")
        }
    }
    
    func addInQeueDownload(imageName: String, urlposter: String, indexPath: IndexPath, idImage: Int ) {
        let operation = DownloadImage(imageName, url: urlposter, idImage: idImage, size: "origin")
        operation.completionBlock = {
            sleep(1)
            DispatchQueue.main.async {
                let NSidImage = NSNumber(value: idImage)
                self.moviePoster.image = APIImage.share.cache.object(forKey: NSidImage)
            }
        }
        operationQueue.addOperation(operation)
    }
}

