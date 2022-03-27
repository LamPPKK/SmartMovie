//
//  PageViewController.swift
//  SmartMovie
//
//  Created by Tùng Lâm on 12/25/21.
//

import UIKit

class PageViewController: UIPageViewController {
    
    fileprivate var items: [UIViewController] = []
    var currentIndex = 0
    let controllerIdentifierArray = ["TabViewController1","TabViewController2","TabViewController3","TabViewController4","TabViewController5"]
    private(set) lazy var orderedViewControllers: [UIViewController] = {
        return [self.newColoredViewController(controllerIdentifier: controllerIdentifierArray[0]),
                self.newColoredViewController(controllerIdentifier: controllerIdentifierArray[1]),
                self.newColoredViewController(controllerIdentifier: controllerIdentifierArray[2]),
                self.newColoredViewController(controllerIdentifier: controllerIdentifierArray[3]),
                self.newColoredViewController(controllerIdentifier: controllerIdentifierArray[4])]}()

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        if let firstViewController = orderedViewControllers.first {
            setViewControllers([firstViewController], direction: .forward, animated: true, completion: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(changeGrid), name: NSNotification.Name("changeGrid"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(seeAllMovie(_:)), name: NSNotification.Name("seeAll"), object: nil)
    }
    
    @objc func seeAllMovie(_ notification: Notification) {
        guard let index = notification.object as? Int else { return }
        print("---- page view: \(index)")
    }
    
    @objc func changeGrid() {
        (orderedViewControllers[0] as? MoviesViewController)?.isGrid.toggle()
        (orderedViewControllers[1] as? PopularViewController)?.isGrid.toggle()
        (orderedViewControllers[2] as? TopRateViewController)?.isGrid.toggle()
        (orderedViewControllers[3] as? UpCommingViewController)?.isGrid.toggle()
        (orderedViewControllers[4] as? NowPlayingViewController)?.isGrid.toggle()
    }
    
    func newColoredViewController(controllerIdentifier: String) -> UIViewController {
        let vc = UIStoryboard(name: "Main", bundle: nil) .
            instantiateViewController(withIdentifier: controllerIdentifier)
        return vc
    }
    
    func setControllerWithIndex(index: Int,direction: UIPageViewController.NavigationDirection ){
        setViewControllers([orderedViewControllers[index]], direction: direction, animated: true, completion: nil)
    }
    
    func changeViewController(currentIndex: Int, nextIndex: Int){
        switch nextIndex {
        case 0:
            if nextIndex>currentIndex{
                setControllerWithIndex(index:0,direction: .forward)
            }else{
                setControllerWithIndex(index :0,direction: .reverse)
            }
        case 1:
            if nextIndex>currentIndex{
                setControllerWithIndex(index :1,direction: .forward)
            }else{
                setControllerWithIndex(index :1,direction: .reverse)
            }
        case 2:
            if nextIndex>currentIndex{
                setControllerWithIndex(index :2,direction: .forward)
            }else{
                setControllerWithIndex(index :2,direction: .reverse)
            }
        case 3:
            if nextIndex>currentIndex{
                setControllerWithIndex(index :3,direction: .forward)
            }else{
                setControllerWithIndex(index :3,direction: .reverse)
            }
        case 4:
            if nextIndex>currentIndex{
                setControllerWithIndex(index :4,direction: .forward)
            }else{
                setControllerWithIndex(index :4,direction: .reverse)
            }
        default:
            if nextIndex>currentIndex{
                setControllerWithIndex(index :0,direction: .forward)
            }else{
                setControllerWithIndex(index:0,direction: .reverse)
            }
        }
    }
}

extension PageViewController: UIPageViewControllerDataSource {
    func pageViewController(_: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = orderedViewControllers.firstIndex(of: viewController) else {
            return nil
        }
        let previousIndex = viewControllerIndex - 1
        guard previousIndex >= 0 else {
            return nil
        }
        guard orderedViewControllers.count > previousIndex else {
            return nil
        }
        return orderedViewControllers[previousIndex]
    }
    func pageViewController(_: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = orderedViewControllers.firstIndex(of: viewController) else {
            return nil
        }
        let nextIndex = viewControllerIndex + 1
        let orderedViewControllersCount = orderedViewControllers.count
        guard orderedViewControllersCount != nextIndex else {
            return nil
        }
        guard orderedViewControllersCount > nextIndex else {
            return nil
        }
        return orderedViewControllers[nextIndex]
    }
    func presentationIndex(for _: UIPageViewController) -> Int {
        guard let firstViewController = viewControllers?.first,
              let firstViewControllerIndex = items.firstIndex(of: firstViewController) else {
            return 0
        }
        return firstViewControllerIndex
    }
}

extension PageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed {
            if let currentViewController = pageViewController.viewControllers?.first,
               let index = orderedViewControllers.firstIndex(of: currentViewController) {
                currentIndex = index
                let indexDict:[String: Int] = ["index": currentIndex]
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "updateTabs"), object: nil, userInfo: indexDict)
            }
        }
    }
}
