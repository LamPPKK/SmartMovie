//
//  TableViewCellOne.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/5/21.
//

import UIKit

class TableViewCellOne: UITableViewCell, UICollectionViewDelegate, UICollectionViewDataSource {
    
    @IBOutlet weak var castView: UICollectionView!
    private let operationQueue = OperationQueue()
    var listCast: [Cast] = [] {
        didSet {
            castView.reloadData()
        }
    }
    override func awakeFromNib() {
        super.awakeFromNib()
        castView.delegate = self
        castView.dataSource = self
        castView.register(UINib(nibName: "OneCollectionViewCell", bundle: nil),forCellWithReuseIdentifier: "OneCollectionViewCell")
        // Initialization code
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Configure the view for the selected state
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return listCast.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "OneCollectionViewCell", for: indexPath)
        if let cell = cell as? OneCollectionViewCell{
            let castInfo = listCast[indexPath.item]
            let NSidImage = NSNumber(value: castInfo.castId)
            cell.imgCell1.image = APIImage.share.cache.object(forKey: NSidImage)
            cell.nameCell1.text = castInfo.castName
            cell.timeCell1.isHidden = true
            cell.likeCell1.isHidden = true
            cell.layer.cornerRadius = 20
            cell.layer.borderWidth = 1
            cell.layer.borderColor = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if listCast[indexPath.row].profilePath == nil {
            return
        }
        if listCast[indexPath.row].isDownload == true {
            return
        } else {
            listCast[indexPath.row].isDownload = true
            guard let poster = listCast[indexPath.row].profilePath else {return}
            addInQeueDownload(imageName:String( listCast[indexPath.row].castId), urlposter: poster, indexPath: indexPath, idImage: listCast[indexPath.row].castId)
        }
    }
    
    func addInQeueDownload(imageName: String, urlposter: String, indexPath: IndexPath, idImage: Int ) {
        let operation = DownloadImage(imageName, url: urlposter, idImage: idImage, size: "w500")
        operation.completionBlock = {
            DispatchQueue.main.async {
                self.castView.reloadItems(at: [indexPath])
            }
        }
        operationQueue.addOperation(operation)
    }
}
extension TableViewCellOne: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        return CGSize(width: 100 , height: 180)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }
}

