//
//  MoreViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/2/21.
//

import UIKit

class MoreViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {

    private var operationQueue = OperationQueue()
    private let apiConnection = APIConnection()
    private var moreURL = "1"
    private var listMovie = [MovieInfo]()
    private var movieGenres: String = ""
    var idGenres: Int = 0
    var pageNum: Int = 1
    private var refreshControl = UIRefreshControl()
    private var genres: String = ""

    @IBOutlet weak var collectionView: UICollectionView!
    
    override func viewDidLoad() {
        setupCollectionView()
        super.viewDidLoad()
        navigationItem.title = "More Movie of Genres"
        // Do any additional setup after loading the view.
        setupCollectionView()
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        collectionView.register(UINib(nibName: "OneCollectionViewCell", bundle: nil),forCellWithReuseIdentifier: "OneCollectionViewCell")
        fetchData(idGenres: idGenres)
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
    
    func fetchData(idGenres: Int) {
        apiConnection.fetchAPIFromURL("api.themoviedb.org/3/discover/movie?api_key=d5b97a6fad46348136d87b78895a0c06&language=en-US&page=\(pageNum)&with_genres=\(idGenres)") { [weak self] (body, errorMessage) in
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
                DispatchQueue.main.async {
                    self.collectionView.reloadData()
                }
            }
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return listMovie.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
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
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController {
            vc.movieID = listMovie[indexPath.row].movieID
            navigationController?.pushViewController(vc, animated: true)
        }
        print("Has been press")
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
}
extension MoreViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: (collectionView.frame.width - 48) / 2 , height: 280)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 8, bottom: 16, right: 8)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        16
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        16
    }
}
