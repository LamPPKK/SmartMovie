//
//  GenresViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class GenresViewController: UIViewController {
    private var viewModel = GenresViewModel()
    @IBOutlet var genresColectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Genres"
        setupBindings()

        genresColectionView.dataSource = self
        genresColectionView.delegate = self
        genresColectionView.register(UINib(nibName: "GenresCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: "GenresCollectionViewCell")
    }

    private func setupBindings() {
        viewModel.reloadCollectionViewClosure = { [weak self] in
            DispatchQueue.main.async {
                self?.genresColectionView.reloadData()
            }
        }

        viewModel.fetchGenres()
    }
}

extension GenresViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.listGenres.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = genresColectionView.dequeueReusableCell(withReuseIdentifier: "GenresCollectionViewCell", for: indexPath) as! GenresCollectionViewCell
        let genre = viewModel.listGenres[indexPath.item]
        cell.nameGenres.text = genre.genresName
        cell.layer.cornerRadius = 10
        return cell
    }
}

extension GenresViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        print(indexPath)
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let vc = storyboard.instantiateViewController(withIdentifier: "MoreViewController") as? MoreViewController {
            vc.idGenres = viewModel.listGenres[indexPath.row].idGenres
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

extension GenresViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        return CGSize(width: UIScreen.main.bounds.width - 50, height: 250)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets
    {
        return UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }
}
