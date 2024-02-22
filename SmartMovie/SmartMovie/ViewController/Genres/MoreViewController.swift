//
//  MoreViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/2/21.
//

import UIKit

class MoreViewController: UIViewController {
    private var viewModel = MoreViewModel()
    private var operationQueue = OperationQueue()

    private var moreURL = "1"

    private var movieGenres: String = ""
    var idGenres: Int = 0

    private var refreshControl = UIRefreshControl()
    private var genres: String = ""

    @IBOutlet var collectionView: UICollectionView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        navigationItem.title = "More Movie of Genres"
            
        setupBindings()
    }
        
    private func setupBindings() {
        viewModel.idGenres = self.idGenres
        viewModel.reloadCollectionViewClosure = { [weak self] in
            DispatchQueue.main.async {
                self?.collectionView.reloadData()
            }
        }
            
        viewModel.fetchMovies()
    }
        
    private func setupCollectionView() {
        collectionView.alwaysBounceVertical = true
        refreshControl.attributedTitle = NSAttributedString(string: "Refreshing")
        refreshControl.addTarget(self, action: #selector(self.refresh), for: .valueChanged)
        collectionView.addSubview(refreshControl)
        collectionView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        collectionView.register(UINib(nibName: "OneCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: "OneCollectionViewCell")
    }
        
    @objc func refresh(_ sender: AnyObject) {
        viewModel.pageNum = 1
        viewModel.fetchMovies()
    }
}

extension MoreViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.listMovie.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "OneCollectionViewCell", for: indexPath) as? OneCollectionViewCell else {
            fatalError("Unable to dequeue OneCollectionViewCell")
        }
        let movieInfo = viewModel.listMovie[indexPath.row]
        let cellViewModel = OneCollectionViewModelCell(movie: movieInfo)
        cell.setupCell(viewModel: cellViewModel)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.row == viewModel.listMovie.count + 1 {
            viewModel.fetchMovies()
        }
    }
}

extension MoreViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController {
            vc.movieID = viewModel.listMovie[indexPath.row].movieID
            navigationController?.pushViewController(vc, animated: true)
        }
        print("Has been press")
    }
    
    func addInQeueDownload(imageName: String, urlposter: String, indexPath: IndexPath, idImage: Int) {
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
                        sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        return CGSize(width: (collectionView.frame.width - 48) / 2, height: 280)
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets
    {
        return UIEdgeInsets(top: 0, left: 8, bottom: 16, right: 8)
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat
    {
        16
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt section: Int) -> CGFloat
    {
        16
    }
}
