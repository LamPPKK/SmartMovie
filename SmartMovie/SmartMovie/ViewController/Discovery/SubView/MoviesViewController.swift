//
//  MoviesViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class MoviesViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    
    @IBOutlet weak var collectionView: UICollectionView!
    private let operationQueue = OperationQueue()
    private let apiService = APIConnection()
    private var listMovie = [MovieInfo]()
    private var popularList = [MovieInfo]()
    private var topRateList = [MovieInfo]()
    private var upComingList = [MovieInfo]()
    private var nowPlayingList = [MovieInfo]()
    private var refreshControl = UIRefreshControl()
    private var arrayTitle: [String] = [" Popular", " Top Rate"," Up Coming" ,"  Now Playing"]
    
    var loadMovie = [Movies]()
    
    var isGrid = true {
        didSet {
            print(isGrid)
            if collectionView != nil {
                collectionView.reloadData()
            }
        }
    }
    let nowPlayingURL = "api.themoviedb.org/3/movie/now_playing?api_key=d5b97a6fad46348136d87b78895a0c06&page=1"
    let popularURL = "api.themoviedb.org/3/movie/popular?api_key=d5b97a6fad46348136d87b78895a0c06&page=1"
    let topRateURL = "api.themoviedb.org/3/movie/top_rated?api_key=d5b97a6fad46348136d87b78895a0c06&page=1"
    let upComingURL = "api.themoviedb.org/3/movie/upcoming?api_key=d5b97a6fad46348136d87b78895a0c06&page=1"
    
    override func viewDidLoad() {
        setupCollectionView()
        super.viewDidLoad()
        fetchAll()
        operationQueue.maxConcurrentOperationCount = 1
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(UINib(nibName: "OneCollectionViewCell", bundle: nil),forCellWithReuseIdentifier: "OneCollectionViewCell")
        collectionView.register(UINib(nibName: "TwoCollectionViewCell", bundle: nil),forCellWithReuseIdentifier: "TwoCollectionViewCell")
        collectionView.register(UINib(nibName: "HeaderCollectReusableView", bundle: nil),forCellWithReuseIdentifier: "HeaderCollectReusableView")
        collectionView.register(UINib(nibName: "HeaderCollectReusableView", bundle: nil),
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: "HeaderCollectReusableView")
        collectionView.reloadData()
        collectionView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        collectionView.prepareForInterfaceBuilder()
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
    private func fetchAll(){
        fetchData(nowPlayingURL)
        fetchData(upComingURL)
        fetchData(topRateURL)
        fetchData(popularURL)
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
            guard let list = result else {
                return
            }
            self.loadMovie.append(list)
            self.listMovie.append(contentsOf: list.results)
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 6
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return loadMovie.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isGrid {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "OneCollectionViewCell", for: indexPath) as? OneCollectionViewCell else {
                fatalError("Unable to dequeue OneCollectionViewCell")
            }
            let movieInfo = listMovie[indexPath.row]
            let cellViewModel = OneCollectionViewModelCell(movie: movieInfo)
            cell.setupCell(viewModel: cellViewModel)
            cell.layer.cornerRadius = 20
            cell.layer.borderWidth = 1
            cell.layer.borderColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TwoCollectionViewCell", for: indexPath)
            if let cell = cell as? TwoCollectionViewCell{
                let movieInfo = loadMovie[indexPath.section].results[indexPath.item]
                cell.nameCell2.text = movieInfo.movieName
                let NSidImage = NSNumber(value: movieInfo.movieID)
                cell.imgCell2.image = APIImage.share.cache.object(forKey: NSidImage)
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
        guard loadMovie.count == 4  else { return }
        if listMovie[indexPath.row].backdropPath == nil {
            return
        }
        if listMovie[indexPath.row].isDownload == true {
            return
        } else {
            listMovie[indexPath.row].isDownload = true
            let movieInfo = loadMovie[indexPath.section].results[indexPath.item]
            guard let poster = movieInfo.posterPath else { return }
            addInQeueDownload(imageName:String( movieInfo.movieID), urlposter: poster, indexPath: indexPath, idImage: movieInfo.movieID)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        guard let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "HeaderCollectReusableView", for: indexPath) as? HeaderCollectReusableView else {
            assert(false, "Unexpected element kind")
        }
        headerView.lblType.text = arrayTitle[indexPath.section]
        headerView.getPageToChange(currentIndex: 0, nextIndex: indexPath.row+1, indexPath: indexPath)
        headerView.delegate = self
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController {
            vc.movieID = listMovie[indexPath.row].movieID
            navigationController?.pushViewController(vc, animated: true)
        }
        print("Has been press")
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        return CGSize(width: UIScreen.main.bounds.width, height: 60.0)
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

extension MoviesViewController: HeaderCollectDelegate {
    func seeAllMovie(indexPath: IndexPath) {
        NotificationCenter.default.post(name: NSNotification.Name("seeAll"), object: indexPath.section + 1)
        let page = PageViewController()
        page.changeViewController(currentIndex: 0, nextIndex: indexPath.section+1)
    }
}

extension MoviesViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if isGrid {
            return CGSize(width: (collectionView.frame.width - 48) / 2 , height: 280)
        }
        else {
            return CGSize(width: collectionView.frame.width - 32, height: 190)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if isGrid {
            return UIEdgeInsets(top: 0, left: 8, bottom: 16, right: 8)

        } else {
            return UIEdgeInsets(top: 0, left: 8, bottom: 16, right: 8)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        16
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        16
    }
}
