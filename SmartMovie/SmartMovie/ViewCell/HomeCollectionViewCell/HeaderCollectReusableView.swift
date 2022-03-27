//
//  HeaderCollectReusableView.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

protocol HeaderCollectDelegate: AnyObject {
    func seeAllMovie(indexPath: IndexPath)
}

class HeaderCollectReusableView: UICollectionReusableView {

    @IBOutlet weak var btnGoto: UIButton!
    @IBOutlet weak var lblType: UILabel!
    weak var delegate: HeaderCollectDelegate?
    var current:Int = 0;
    var nextInt:Int = 0;
    var indexPathHeader: IndexPath?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    func getPageToChange(currentIndex:Int, nextIndex:Int, indexPath: IndexPath) {
        current = currentIndex
        nextInt = nextIndex
        indexPathHeader = indexPath
    }
    
    
    @IBAction func changePage(_ sender: Any) {
        // chưa truy cập đk vào class
        guard let index = indexPathHeader else {
            return
        }
        delegate?.seeAllMovie(indexPath: index)
        let page = PageViewController()
        page.changeViewController(currentIndex: current, nextIndex: nextInt)
        //Print(nextInt)
    }
}
