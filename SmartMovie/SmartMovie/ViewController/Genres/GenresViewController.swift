//
//  GenresViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class GenresViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    
    private let apiService = APIConnection()
    var genresURL = "api.themoviedb.org/3/genre/movie/list?api_key=d5b97a6fad46348136d87b78895a0c06&language=en-US"
    var listGenres = [Genres]()
    
    @IBOutlet weak var genresColectionView: UICollectionView!
    
    override func viewDidLoad() {
        navigationItem.title = "Genres"
        genresColectionView.dataSource = self
        genresColectionView.delegate = self
        genresColectionView.register(UINib(nibName: "GenresCollectionViewCell", bundle: nil),forCellWithReuseIdentifier: "GenresCollectionViewCell")
        super.viewDidLoad()
        fetchData(genresURL)
        print(listGenres)
        // Do any additional setup after loading the view.
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
            }
        }
    }
    
    private func convertData(_ data: String) {
        let responseData = Data(data.utf8)
        let decoder = JSONDecoder()
        var result: Genre?
        
        do {
            result = try decoder.decode(Genre.self, from: responseData)
            if let list = result?.genres {
                print(list)
                self.listGenres.append(contentsOf: list)
                DispatchQueue.main.async {
                    self.genresColectionView.reloadData()
                }
            }
        } catch let error {
            print("Failed to decode JSON \(error)")
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return listGenres.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = genresColectionView.dequeueReusableCell(withReuseIdentifier: "GenresCollectionViewCell", for: indexPath)
        if let cell = cell as? GenresCollectionViewCell{
            let Genres = listGenres[indexPath.item]
            cell.nameGenres.text = Genres.genresName
            cell.layer.cornerRadius = 10
        }
        return cell
    }
    
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            print(indexPath)
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            if let vc = storyboard.instantiateViewController(withIdentifier: "MoreViewController") as? MoreViewController {
                vc.idGenres = listGenres[indexPath.row].idGenres
                navigationController?.pushViewController(vc, animated: true)
            }
        }
}

extension GenresViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: UIScreen.main.bounds.width - 50, height: 250)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }
}
