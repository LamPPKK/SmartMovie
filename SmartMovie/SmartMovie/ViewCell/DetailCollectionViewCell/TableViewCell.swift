//
//  TableViewCell.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 7/5/21.
//

import UIKit

class TableViewCell: UITableViewHeaderFooterView {

    @IBOutlet var mainView: UIView!
    @IBOutlet weak var lblName: UILabel!
    
    var name: String?
    
    override init(reuseIdentifier: String?) {
            super.init(reuseIdentifier: reuseIdentifier)
            loadNib()
        }
        
        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
            loadNib()
        }
        
        private func loadNib() {
            Bundle.main.loadNibNamed("FhardView", owner: self, options: nil)
            addSubview(mainView)
            mainView.frame = self.bounds
            mainView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        
        func configure(with name: String) {
            lblName.text = name
        }
}
