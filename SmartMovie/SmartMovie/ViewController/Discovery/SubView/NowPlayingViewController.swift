//
//  NowPlayingViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class NowPlayingViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    
    @IBOutlet weak var collectionView: UICollectionView!
    private let operationQueue = OperationQueue()
    private let apiService = APIConnection()
    var refreshControl = UIRefreshControl()
    var listMovie = [MovieInfo]()
    private var seeAll: Int?
    var cellType = "0"
    
    var upComingURL = "api.themoviedb.org/3/movie/now_playing?api_key=d5b97a6fad46348136d87b78895a0c06&page="
    var pageNumber: Int = 1 {
        didSet {
            upComingURL = "api.themoviedb.org/3/movie/now_playing?api_key=d5b97a6fad46348136d87b78895a0c06&page=\(pageNumber)"
        }
    }
    
    var isGrid = true {
        didSet {
            if collectionView != nil {
                collectionView.reloadData()
            }
        }
    }

    
    override func viewDidLoad() {
        setupCollectionView()
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        fetchData(upComingURL)
        print(listMovie)
        operationQueue.maxConcurrentOperationCount = 1
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(UINib(nibName: "OneCollectionViewCell", bundle: nil),forCellWithReuseIdentifier: "OneCollectionViewCell")
        collectionView.register(UINib(nibName: "TwoCollectionViewCell", bundle: nil),forCellWithReuseIdentifier: "TwoCollectionViewCell")
        NotificationCenter.default.addObserver(self, selector: #selector(cellGrid), name: Notification.Name("changeGrid"), object: nil)
        collectionView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    }
    func setupCollectionView(){
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        self.refreshControl = UIRefreshControl()
        self.refreshControl.attributedTitle = NSAttributedString(string: "Refreshing")
        self.refreshControl.addTarget(self, action: #selector(self.refresh), for: .valueChanged)
        collectionView!.addSubview(refreshControl)
    }
    @objc func refresh(_ sender:AnyObject) {
        self.collectionView.reloadData()
        self.refreshControl.endRefreshing()
    }
    @objc
    func cellGrid() {
        isGrid = !isGrid
        print(isGrid)
        collectionView.reloadData()
    }
    
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
                DispatchQueue.main.async {
                    self.collectionView.reloadData()
                }
            }
        }
    }
    
    private func convertData(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        var result: Movies?
        
        do {
            result = try decoder.decode(Movies.self, from: responseData)
            if let list = result?.results {
                print(list)
                self.listMovie.append(contentsOf: list)
            }
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return listMovie.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isGrid {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "OneCollectionViewCell", for: indexPath)
            if let cell = cell as? OneCollectionViewCell{
                let movieInfo = listMovie[indexPath.item]
                let NSidImage = NSNumber(value: movieInfo.movieID)
                cell.imgCell1.image = APIImage.share.cache.object(forKey: NSidImage)
                cell.nameCell1.text = movieInfo.movieName
                cell.showTime(runtime: movieInfo.rumtime)
                cell.fetchData(movieIDs: movieInfo.movieID)
                cell.setupCell(data: movieInfo)
                cell.movieIDs = movieInfo.movieID
                cell.layer.cornerRadius = 20
                cell.layer.borderWidth = 1
                cell.layer.borderColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TwoCollectionViewCell", for: indexPath)
            if let cell = cell as? TwoCollectionViewCell{
                let movieInfo = listMovie[indexPath.item]
                cell.nameCell2.text = movieInfo.movieName
                cell.showImageCell2(idImage: movieInfo.movieID)
                cell.showTime(runtime: movieInfo.rumtime)
                cell.moreCell2.text = movieInfo.overView
                cell.fetchData(movieIDs: movieInfo.movieID)
                cell.setupCell(data: movieInfo)
                cell.movieIDs = movieInfo.movieID
                cell.layer.cornerRadius = 10
            }
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if listMovie[indexPath.row].backdropPath == nil {
            return
        }
        if listMovie[indexPath.row].isDownload == true {
            return
        } else {
            listMovie[indexPath.row].isDownload = true
            guard let poster = listMovie[indexPath.row].posterPath else {return}
            addInQeueDownload(imageName:String( listMovie[indexPath.row].movieID), urlposter: poster, indexPath: indexPath, idImage: listMovie[indexPath.row].movieID)
        }
        if indexPath.row == (listMovie.count - 1 ) {
            pageNumber += 1
            fetchData(upComingURL)
        }
    }
    
    func addInQeueDownload(imageName: String, urlposter: String, indexPath: IndexPath, idImage: Int ) {
        let operation = DownloadImage(imageName, url: urlposter, idImage: idImage, size: "w500")
        operation.completionBlock = {
            DispatchQueue.main.async {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
        operationQueue.addOperation(operation)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController {
            vc.movieID = listMovie[indexPath.row].movieID
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

extension NowPlayingViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if isGrid {
            return CGSize(width: (collectionView.frame.width - 50) / 2 , height: 280)
        }
        else {
            return CGSize(width: collectionView.frame.width - 35, height: 190)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if isGrid {
            return UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 8)

        } else {
            return UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 8)

        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        8
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        8
    }
}
