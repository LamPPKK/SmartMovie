//
//  PopularViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

final class PopularViewController: UIViewController {
    // MARK: - Variable

    private let apiService = APIConnection()
    private var refreshControl = UIRefreshControl()
    private var listMovie = [MovieInfo]()
    private var seeAll: Int?
    private var cellType = "0"
    
    private var topRateURL = "api.themoviedb.org/3/movie/popular?api_key=d5b97a6fad46348136d87b78895a0c06&page="
    private var pageNumber: Int = 1 {
        didSet {
            topRateURL = "api.themoviedb.org/3/movie/popular?api_key=d5b97a6fad46348136d87b78895a0c06&page=\(pageNumber)"
        }
    }
    
    var isGrid = true {
        didSet {
            if collectionView != nil {
                collectionView.reloadData()
            }
        }
    }
    
    // MARK: - IBOutlet

    @IBOutlet var collectionView: UICollectionView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Popular List"
        setupCollectionView()
        fetchData(topRateURL)
    }
    
    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(UINib(nibName: "NewCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: "NewCollectionViewCell")
        collectionView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        NotificationCenter.default.addObserver(self, selector: #selector(cellGrid), name: Notification.Name("changeGrid"), object: nil)
        setupLoadmore()
    }
    
    private func setupLoadmore() {
        refreshControl = UIRefreshControl()
        refreshControl.attributedTitle = NSAttributedString(string: "Refreshing")
        refreshControl.addTarget(self, action: #selector(self.refresh), for: .valueChanged)
        collectionView.addSubview(refreshControl)
    }
    
    @objc
    func refresh(_ sender: AnyObject) {
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
        apiService.fetchAPIFromURL(url) { [weak self] body, error in
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
        } catch {
            print("Failed to decode JSON \(error)")
        }
    }
}

// MARK: - UICollectionViewDelegate, UICollectionViewDataSource

extension PopularViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return listMovie.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "NewCollectionViewCell", for: indexPath) as? NewCollectionViewCell else {
            return UICollectionViewCell()
        }
        let movieInfo = listMovie[indexPath.item]
        cell.movieIDs = movieInfo.movieID
        cell.setupCell(data: movieInfo)
        cell.layer.cornerRadius = 5
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.row == (listMovie.count - 4) {
            pageNumber += 1
            fetchData(topRateURL)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController {
            vc.movieID = listMovie[indexPath.row].movieID
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension PopularViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        if isGrid {
            return CGSize(width: (collectionView.frame.width - 48) / 2, height: 280)
        } else {
            return CGSize(width: collectionView.frame.width - 35, height: 190)
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
