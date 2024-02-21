//
//  SearchViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

protocol DelegateResultSearch: AnyObject {
    func reloadResultSearch(dataSearch: SearchResults)
}

class SearchViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UISearchBarDelegate {

    @IBOutlet weak var searchColectionView: UICollectionView!
    @IBOutlet weak var searchBarView: UISearchBar!
    private let operationQueue = OperationQueue()
    weak var delegate: DelegateResultSearch?
    let apiConnection = APIConnection()
    var allData: [SearchResults] = []
    var searchResults: SearchResults?
    var moviName: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        searchColectionView.dataSource = self
        searchColectionView.delegate = self
        searchColectionView.register(UINib(nibName: "SearchCell", bundle: nil),forCellWithReuseIdentifier: "SearchCell")
        searchBarView.delegate = self
        operationQueue.maxConcurrentOperationCount = 1
        searchBarView.isHidden = false
    }

    func fetchListID(movieSearch: String) {
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
                self?.convertData(body)
            }
        }
    }
    private func convertData(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        var responseEntity: SearchResults?
        do {
            responseEntity = try decoder.decode(SearchResults.self, from: responseData)
            if let responseEntity = responseEntity {
                delegate?.reloadResultSearch(dataSearch: responseEntity)
            }
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        self.searchBarView.showsCancelButton = true
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchBarView.text == nil || searchBar.text == "" {
            view.endEditing(true)
            self.searchBarView.showsCancelButton = false
        } else {
            moviName = searchBarView.text ?? ""
            let movinames = moviName.replacingOccurrences(of: " ", with: "%20")
            delegate = self
            fetchListID(movieSearch: movinames)
        }
    }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.view.endEditing(true)
        self.searchBarView.showsCancelButton = false
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return searchResults?.results.count ?? 0
    }
    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = searchColectionView.dequeueReusableCell(withReuseIdentifier: "SearchCell", for: indexPath)
        if let cell = cell as? SearchCell {
            if let searchResult = searchResults {
                cell.layer.cornerRadius = 10
                cell.drawStar(scoreAverage: searchResult.results[indexPath.row].voteAverage )
                cell.movieName.text = searchResult.results[indexPath.row].movieName
                cell.genresMove(genresMove: searchResult.results[indexPath.row].genresMovie)
                cell.movieIDs = searchResult.results[indexPath.row].movieID
                cell.showImage(idImage: searchResult.results[indexPath.row].movieID)
                if searchResult.results[indexPath.row].backdropPath == "" {
                    return cell
                }
                if searchResults?.results[indexPath.row].isDownload == true {
                    return cell
                } else {
                    searchResults?.results[indexPath.row].isDownload = true
                    let imageName = searchResult.results[indexPath.row].backdropPath?.replacingOccurrences(of: "/", with: "")
                    addInQeueDownload(imageName: imageName?.replacingOccurrences(of: ".jpg", with: "") ?? "" ,
                                      urlposter: searchResult.results[indexPath.row].backdropPath ?? "" ,
                                      indexPath: indexPath,
                                      idImage: searchResult.results[indexPath.row].movieID)
                }
                cell.layer.cornerRadius = 10
            }
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let searchResult = searchResults {
            if searchResult.results[indexPath.row].backdropPath == nil {
                return
            }
            if searchResults?.results[indexPath.row].isDownload == true {
                return
            } else {
                searchResults?.results[indexPath.row].isDownload = true
                let imageName = searchResult.results[indexPath.row].backdropPath?.replacingOccurrences(of: "/", with: "")
                addInQeueDownload(imageName: imageName?.replacingOccurrences(of: ".jpg", with: "") ?? "" ,
                                  urlposter: searchResult.results[indexPath.row].backdropPath ?? "" ,
                                  indexPath: indexPath,
                                  idImage: searchResult.results[indexPath.row].movieID)
            }
        }
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        print(indexPath)
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "DetailViewController") as? DetailViewController {
            vc.movieID = searchResults?.results[indexPath.row].movieID ?? 0
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    

}
extension SearchViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: UIScreen.main.bounds.width - 50, height: 250)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }
}

extension SearchViewController: DelegateResultSearch {
    func reloadResultSearch(dataSearch: SearchResults) {
        operationQueue.cancelAllOperations()
        searchResults = dataSearch
        DispatchQueue.main.sync {
            self.searchColectionView.reloadData()
        }
    }
}
extension SearchViewController {
    func addInQeueDownload(imageName: String, urlposter: String, indexPath: IndexPath, idImage: Int ) {
        let operation = DownloadImage(imageName, url: urlposter, idImage: idImage, size: "w500")
        operation.completionBlock = {
            sleep(1)
            DispatchQueue.main.async {
                self.searchColectionView.reloadItems(at: [indexPath])
            }
        }
        operationQueue.addOperation(operation)
    }
}
