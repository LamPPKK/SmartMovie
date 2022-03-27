//
//  HomeViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class HomeViewController: UIViewController {
    
    @IBOutlet private weak var changeViewBTN: UIButton!
    var currentSelectedBtn = 0
    var isGrid = true
    
    @IBOutlet weak var tabButton1: UIButton!
    @IBOutlet weak var tabButton2: UIButton!
    @IBOutlet weak var tabButton3: UIButton!
    @IBOutlet weak var tabButton4: UIButton!
    @IBOutlet weak var tabButton5: UIButton!
    @IBOutlet weak var tabContainerView: UIView!
    @IBOutlet weak var tabContentView: UIView!
    
    let myPageView = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "pageview") as! PageViewController
    var pageVC = PageViewController(transitionStyle:
                                        UIPageViewController.TransitionStyle.scroll, navigationOrientation:
                                            UIPageViewController.NavigationOrientation.horizontal, options: nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateButtons(selectedBtn: tabButton1,
                      unselectedBtn1: tabButton2,
                      unselectedBtn2: tabButton3,
                      unselectedBtn3: tabButton4,
                      unselectedBtn4: tabButton5)
        tabButton1.setTitle("Movies", for: .normal)
        tabButton2.setTitle("Popular", for: .normal)
        tabButton3.setTitle("Top Rate", for: .normal)
        tabButton4.setTitle("Up Coming", for: .normal)
        tabButton5.setTitle("Now Playing", for: .normal)
        self.addChild(pageVC)
        self.tabContentView.addSubview(pageVC.view)
        NotificationCenter.default.addObserver(self, selector: #selector(self.changeIndex(_:)), name: NSNotification.Name(rawValue: "updateTabs"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(seeAllMovie(_:)), name: NSNotification.Name("seeAll"), object: nil)
        changeBTN()
    }
    
    @objc
    func seeAllMovie(_ notification: Notification) {
        guard let index = notification.object as? Int else { return }
        print("---- page view: \(index)")
        pageVC.changeViewController(currentIndex: 0, nextIndex: index)
        updateButton(index)
    }
    
    @objc func changeIndex(_ notification: NSNotification){
        if let dict = notification.userInfo as NSDictionary? {
            if let index = dict["index"] as? Int{
                updateButton(index)
            }
        }
    }
    func changeBTN(){
        if !isGrid {
            changeViewBTN.setImage(UIImage(systemName: "rectangle.grid.1x2.fill"), for: .normal)
        }
        else {
            changeViewBTN.setImage(UIImage(systemName: "square.grid.2x2.fill"), for: .normal)
        }
    }
    
    func updateButton(_ index:Int) {
        switch index {
        case 0:
            updateButtons(selectedBtn: tabButton1,
                          unselectedBtn1: tabButton2,
                          unselectedBtn2: tabButton3,
                          unselectedBtn3: tabButton4,
                          unselectedBtn4: tabButton5)
            currentSelectedBtn = 0
            
        case 1:
            updateButtons(selectedBtn: tabButton2,
                          unselectedBtn1: tabButton1,
                          unselectedBtn2: tabButton3,
                          unselectedBtn3: tabButton4,
                          unselectedBtn4: tabButton5)
            currentSelectedBtn = 1
            
        case 2:
            updateButtons(selectedBtn: tabButton3,
                          unselectedBtn1: tabButton1,
                          unselectedBtn2: tabButton2,
                          unselectedBtn3: tabButton4,
                          unselectedBtn4: tabButton5)
            currentSelectedBtn = 2
            
        case 3:
            updateButtons(selectedBtn: tabButton4,
                          unselectedBtn1: tabButton1,
                          unselectedBtn2: tabButton2,
                          unselectedBtn3: tabButton3,
                          unselectedBtn4: tabButton5)
            currentSelectedBtn = 3
            
        case 4:
            updateButtons(selectedBtn: tabButton5,
                          unselectedBtn1: tabButton1,
                          unselectedBtn2: tabButton2,
                          unselectedBtn3: tabButton3,
                          unselectedBtn4: tabButton4)
            currentSelectedBtn = 4
            
            
        default:
            updateButtons(selectedBtn: tabButton1,
                          unselectedBtn1: tabButton2,
                          unselectedBtn2: tabButton3,
                          unselectedBtn3: tabButton4,
                          unselectedBtn4: tabButton5)
            currentSelectedBtn = 0
        }    }
    
    @IBAction func tab1Clicled(_sender: UIButton){
        updateButtons(selectedBtn: tabButton1,
                      unselectedBtn1: tabButton2,
                      unselectedBtn2: tabButton3,
                      unselectedBtn3: tabButton4,
                      unselectedBtn4: tabButton5)
        pageVC.changeViewController(currentIndex: currentSelectedBtn, nextIndex: 0)
        currentSelectedBtn=0
        
    }
    @IBAction func tab2Clicled(_sender: UIButton){
        updateButtons(selectedBtn: tabButton2,
                      unselectedBtn1: tabButton1,
                      unselectedBtn2: tabButton3,
                      unselectedBtn3: tabButton4,
                      unselectedBtn4: tabButton5)
        pageVC.changeViewController(currentIndex: currentSelectedBtn, nextIndex: 1)
        currentSelectedBtn=1
        
    }
    @IBAction func tab3Clicled(_sender: UIButton){
        updateButtons(selectedBtn: tabButton3,
                      unselectedBtn1: tabButton2,
                      unselectedBtn2: tabButton1,
                      unselectedBtn3: tabButton4,
                      unselectedBtn4: tabButton5)
        pageVC.changeViewController(currentIndex: currentSelectedBtn, nextIndex: 2)
        currentSelectedBtn=2
        
    }
    
    @IBAction func tab4Clicled(_sender: UIButton){
        updateButtons(selectedBtn: tabButton4,
                      unselectedBtn1: tabButton2,
                      unselectedBtn2: tabButton3,
                      unselectedBtn3: tabButton1,
                      unselectedBtn4: tabButton5)
        pageVC.changeViewController(currentIndex: currentSelectedBtn, nextIndex: 3)
        currentSelectedBtn=3
        
    }
    
    @IBAction func tab5Clicled(_sender: UIButton){
        updateButtons(selectedBtn: tabButton5,
                      unselectedBtn1: tabButton2,
                      unselectedBtn2: tabButton3,
                      unselectedBtn3: tabButton4,
                      unselectedBtn4: tabButton1)
        pageVC.changeViewController(currentIndex: currentSelectedBtn, nextIndex: 4)
        currentSelectedBtn = 4
        
    }
    @IBAction func changeCell(_sender: UIButton){
        isGrid = !isGrid
        changeBTN()
        NotificationCenter.default.post(name: NSNotification.Name("changeGrid"), object: nil)
    }
    
    func updateButtons(selectedBtn: UIButton, unselectedBtn1: UIButton, unselectedBtn2: UIButton, unselectedBtn3: UIButton, unselectedBtn4: UIButton){
        
        selectedBtn.setTitleColor(.white, for: .normal)
        selectedBtn.setTitleColor(.white, for: .selected)
        selectedBtn.backgroundColor = .systemTeal
        selectedBtn.layer.cornerRadius = 10
        
        unselectedBtn1.setTitleColor(.black, for: .normal)
        unselectedBtn1.setTitleColor(.black, for: .selected)
        unselectedBtn1.backgroundColor = .clear
        unselectedBtn1.layer.cornerRadius = 10
        
        unselectedBtn2.setTitleColor(.black, for: .normal)
        unselectedBtn2.setTitleColor(.black, for: .selected)
        unselectedBtn2.backgroundColor = .clear
        unselectedBtn2.layer.cornerRadius = 10
        
        unselectedBtn3.setTitleColor(.black, for: .normal)
        unselectedBtn3.setTitleColor(.black, for: .selected)
        unselectedBtn3.backgroundColor = .clear
        unselectedBtn3.layer.cornerRadius = 10
        
        unselectedBtn4.setTitleColor(.black, for: .normal)
        unselectedBtn4.setTitleColor(.black, for: .selected)
        unselectedBtn4.backgroundColor = .clear
        unselectedBtn4.layer.cornerRadius = 10
        
    }
    
}
