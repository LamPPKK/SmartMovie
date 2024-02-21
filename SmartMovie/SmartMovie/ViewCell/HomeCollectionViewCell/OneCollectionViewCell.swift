//
//  OneCollectionViewCell.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

protocol OneCollectionViewCellDelegate: AnyObject {
    func didTapFavoriteButton(inCell cell: OneCollectionViewCell)
}

class OneCollectionViewCell: UICollectionViewCell {
    weak var delegate: OneCollectionViewCellDelegate?
    @IBOutlet var starIMG: UIButton!
    @IBOutlet var imgCell1: UIImageView!
    @IBOutlet var nameCell1: UILabel!
    @IBOutlet var timeCell1: UILabel!
    @IBOutlet var likeCell1: UIButton!

    @IBAction func funcsetStar(_ sender: Any) {
        delegate?.didTapFavoriteButton(inCell: self)
    }

    var viewModel: OneCollectionViewModelCell? {
        didSet {
            configureCell()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    func setupCell(viewModel: OneCollectionViewModelCell) {
        self.viewModel = viewModel
        viewModel.didUpdate = { [weak self] in
            self?.configureCell()
        }
    }

    private func configureCell() {
        guard let viewModel = self.viewModel else { return }
        nameCell1.text = viewModel.movieName
        timeCell1.text = viewModel.runtimeText
        starIMG.setImage(viewModel.isFavorite ? UIImage(systemName: "star.fill") : UIImage(systemName: "star"), for: .normal)
        if let imageUrl = viewModel.imageUrl {
            loadImage(from: imageUrl)
        }
    }

    private func loadImage(from url: URL) {
        imgCell1.image = nil
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.imgCell1.image = UIImage(data: data)
            }
        }.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imgCell1.image = nil
        starIMG.imageView?.image = nil
    }
}
