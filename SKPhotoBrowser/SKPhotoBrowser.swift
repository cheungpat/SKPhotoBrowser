//
//  SKPhotoBrowser.swift
//  SKViewExample
//
//  Created by suzuki_keishi on 2015/10/01.
//  Copyright © 2015 suzuki_keishi. All rights reserved.
//

import UIKit

@objc public protocol SKPhotoBrowserDelegate {
    optional func didShowPhotoAtIndex(index: Int)
    optional func willDismissAtPageIndex(index: Int)
    optional func willShowActionSheet(photoIndex: Int)
    optional func didDismissAtPageIndex(index: Int)
    optional func didDismissActionSheetWithButtonIndex(buttonIndex: Int, photoIndex: Int)
    optional func removePhoto(browser: SKPhotoBrowser, index: Int, reload: (() -> Void))
    optional func viewForPhoto(browser: SKPhotoBrowser, index: Int) -> UIView?
}

public let SKPHOTO_LOADING_DID_END_NOTIFICATION = "photoLoadingDidEndNotification"

// MARK: - SKPhotoBrowser
public class SKPhotoBrowser: UIViewController, UIScrollViewDelegate {
    
    final let pageIndexTagOffset: Int = 1000
    // animation property
    var animationDuration: NSTimeInterval {
        if bounceAnimation {
            return 0.5
        }
        return 0.35
    }
    var animationDamping: CGFloat {
        if bounceAnimation {
            return 0.8
        }
        return 1
    }
    
    // device property
    final let screenBound = UIScreen.mainScreen().bounds
    var screenWidth: CGFloat { return screenBound.size.width }
    var screenHeight: CGFloat { return screenBound.size.height }
    
    // custom abilities
    public var displayAction: Bool = true
    public var shareExtraCaption: String? = nil
    public var actionButtonTitles: [String]?
    public var displayToolbar: Bool = true
    public var displayCounterLabel: Bool = true
    public var displayBackAndForwardButton: Bool = true
    public var disableVerticalSwipe: Bool = false
    public var isForceStatusBarHidden: Bool = false
    public var displayDeleteButton = false
    public var displayCloseButton = true // default is true
    /// If it is true displayCloseButton will be false
    public var displayCustomCloseButton = false
    /// If it is true displayDeleteButton will be false
    public var displayCustomDeleteButton = false
    public var bounceAnimation = false
    public var enableZoomBlackArea = true
    
    // actions
    private var activityViewController: UIActivityViewController!
    
    // tool for controls
    private var applicationWindow: UIWindow!
    private var toolBar: UIToolbar!
    private var toolCounterLabel: UILabel!
    private var toolCounterButton: UIBarButtonItem!
    private var toolPreviousButton: UIBarButtonItem!
    private var toolActionButton: UIBarButtonItem!
    private var toolNextButton: UIBarButtonItem!
    private var pagingScrollView: UIScrollView!
    private var panGesture: UIPanGestureRecognizer!
    // MARK: close button
    private var closeButton: UIButton!
    private var closeButtonShowFrame: CGRect!
    private var closeButtonHideFrame: CGRect!
    // MARK: delete button
    private var deleteButton: UIButton!
    private var deleteButtonShowFrame: CGRect!
    private var deleteButtonHideFrame: CGRect!
    
    // MARK: - custom buttons
    // MARK: CustomCloseButton
    private var customCloseButton: UIButton!
    public var customCloseButtonShowFrame: CGRect!
    public var customCloseButtonHideFrame: CGRect!
    public var customCloseButtonImage: UIImage!
    public var customCloseButtonEdgeInsets: UIEdgeInsets!
    
    // MARK: CustomDeleteButton
    private var customDeleteButton: UIButton!
    public var customDeleteButtonShowFrame: CGRect!
    public var customDeleteButtonHideFrame: CGRect!
    public var customDeleteButtonImage: UIImage!
    public var customDeleteButtonEdgeInsets: UIEdgeInsets!
    
    // photo's paging
    private var visiblePages = [SKZoomingScrollView]()//: Set<SKZoomingScrollView> = Set()
    private var recycledPages = [SKZoomingScrollView]()
    
    private var initialPageIndex: Int = 0
    private var currentPageIndex: Int = 0
    
    // senderView's property
    private var senderViewForAnimation: UIView?
    private var senderViewOriginalFrame: CGRect = CGRect.zero
    private var senderOriginImage: UIImage!
    
    private var resizableImageView: UIImageView = UIImageView()
    
    // for status check property
    private var isDraggingPhoto: Bool = false
    private var isEndAnimationByToolBar: Bool = true
    private var isViewActive: Bool = false
    private var isPerformingLayout: Bool = false
    private var isStatusBarOriginallyHidden: Bool = false
    
    // scroll property
    private var firstX: CGFloat = 0.0
    private var firstY: CGFloat = 0.0
    
    // timer
    private var controlVisibilityTimer: NSTimer!
    
    // delegate
    public weak var delegate: SKPhotoBrowserDelegate?
    
    // helpers which often used
    private let bundle = NSBundle(forClass: SKPhotoBrowser.self)
    
    // photos
    var photos: [SKPhotoProtocol] = [SKPhotoProtocol]()
    var numberOfPhotos: Int {
        return photos.count
    }
    // MARK - Initializer
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    public override init(nibName nibNameOrNil: String!, bundle nibBundleOrNil: NSBundle!) {
        super.init(nibName: nil, bundle: nil)
        setup()
    }
    
    public convenience init(photos:[ AnyObject]) {
        self.init(nibName: nil, bundle: nil)
        for anyObject in photos {
            if let photo = anyObject as? SKPhotoProtocol {
                photo.checkCache()
                self.photos.append(photo)
            }
        }
    }
    
    public convenience init(originImage: UIImage, photos: [AnyObject], animatedFromView: UIView) {
        self.init(nibName: nil, bundle: nil)
        self.senderOriginImage = originImage
        self.senderViewForAnimation = animatedFromView
        for anyObject in photos {
            if let photo = anyObject as? SKPhotoProtocol {
                photo.checkCache()
                self.photos.append(photo)
            }
        }
    }
    
    deinit {
        pagingScrollView = nil
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func setup() {
        applicationWindow = (UIApplication.sharedApplication().delegate?.window)!
        
        modalPresentationStyle = UIModalPresentationStyle.Custom
        modalPresentationCapturesStatusBarAppearance = true
        modalTransitionStyle = UIModalTransitionStyle.CrossDissolve
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "handleSKPhotoLoadingDidEndNotification:", name: SKPHOTO_LOADING_DID_END_NOTIFICATION, object: nil)
    }
    
    // MARK: - override
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.blackColor()
        view.clipsToBounds = true
        
        // setup paging
        let pagingScrollViewFrame = frameForPagingScrollView()
        pagingScrollView = UIScrollView(frame: pagingScrollViewFrame)
        pagingScrollView.pagingEnabled = true
        pagingScrollView.delegate = self
        pagingScrollView.showsHorizontalScrollIndicator = true
        pagingScrollView.showsVerticalScrollIndicator = true
        pagingScrollView.backgroundColor = UIColor.blackColor()
        pagingScrollView.contentSize = contentSizeForPagingScrollView()
        view.addSubview(pagingScrollView)
        
        // toolbar
        toolBar = UIToolbar(frame: frameForToolbarAtOrientation())
        toolBar.backgroundColor = UIColor.clearColor()
        toolBar.clipsToBounds = true
        toolBar.translucent = true
        toolBar.setBackgroundImage(UIImage(), forToolbarPosition: .Any, barMetrics: .Default)
        view.addSubview(toolBar)
        
        if !displayToolbar {
            toolBar.hidden = true
        }
        
        // arrows:back
        let previousBtn = UIButton(type: .Custom)
        let previousImage = UIImage(named: "SKPhotoBrowser.bundle/images/btn_common_back_wh", inBundle: bundle, compatibleWithTraitCollection: nil) ?? UIImage()
        previousBtn.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        previousBtn.imageEdgeInsets = UIEdgeInsetsMake(13.25, 17.25, 13.25, 17.25)
        previousBtn.setImage(previousImage, forState: .Normal)
        previousBtn.addTarget(self, action: "gotoPreviousPage", forControlEvents: .TouchUpInside)
        previousBtn.contentMode = .Center
        toolPreviousButton = UIBarButtonItem(customView: previousBtn)
        
        // arrows:next
        let nextBtn = UIButton(type: .Custom)
        let nextImage = UIImage(named: "SKPhotoBrowser.bundle/images/btn_common_forward_wh", inBundle: bundle, compatibleWithTraitCollection: nil) ?? UIImage()
        nextBtn.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        nextBtn.imageEdgeInsets = UIEdgeInsetsMake(13.25, 17.25, 13.25, 17.25)
        nextBtn.setImage(nextImage, forState: .Normal)
        nextBtn.addTarget(self, action: "gotoNextPage", forControlEvents: .TouchUpInside)
        nextBtn.contentMode = .Center
        toolNextButton = UIBarButtonItem(customView: nextBtn)
        
        toolCounterLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 95, height: 40))
        toolCounterLabel.textAlignment = .Center
        toolCounterLabel.backgroundColor = UIColor.clearColor()
        toolCounterLabel.font  = UIFont(name: "Helvetica", size: 16.0)
        toolCounterLabel.textColor = UIColor.whiteColor()
        toolCounterLabel.shadowColor = UIColor.darkTextColor()
        toolCounterLabel.shadowOffset = CGSize(width: 0.0, height: 1.0)
        
        toolCounterButton = UIBarButtonItem(customView: toolCounterLabel)
        
        // starting setting
        setCustomSetting()
        setSettingCloseButton()
        setSettingDeleteButton()
        setSettingCustomCloseButton()
        setSettingCustomDeleteButton()
        
        // action button
        toolActionButton = UIBarButtonItem(barButtonSystemItem: .Action, target: self, action: "actionButtonPressed")
        toolActionButton.tintColor = .whiteColor()
        
        // gesture
        panGesture = UIPanGestureRecognizer(target: self, action: "panGestureRecognized:")
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        
        // transition (this must be last call of view did load.)
        performPresentAnimation()
    }
    
    public override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(true)
        reloadData()
        
        var i = 0
        for photo: SKPhotoProtocol in photos {
            photo.index = i
            i = i + 1
        }
    }
    
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        isPerformingLayout = true
        pagingScrollView.frame = frameForPagingScrollView()
        pagingScrollView.contentSize = contentSizeForPagingScrollView()
        // resize frames of buttons after the device rotation
        frameForButton()
        // this algorithm resizes the current image after device rotation
        if visiblePages.count > 0 {
            for page in visiblePages {
                page.frame = frameForPageAtIndex(currentPageIndex)
                page.setMaxMinZoomScalesForCurrentBounds()
                if page.captionView != nil {
                    page.captionView.frame = frameForCaptionView(page.captionView, index: currentPageIndex)
                }
            }
        }

        pagingScrollView.contentOffset = contentOffsetForPageAtIndex(currentPageIndex)
        // where did start
        didStartViewingPageAtIndex(currentPageIndex)
        
        toolBar.frame = frameForToolbarAtOrientation()
        isPerformingLayout = false
    }
    
    public override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(true)
        isViewActive = true
    }
    
    public override func prefersStatusBarHidden() -> Bool {
        if isForceStatusBarHidden {
            return true
        }
        
        if isDraggingPhoto {
            if isStatusBarOriginallyHidden {
                return true
            } else {
                return false
            }
        } else {
            return areControlsHidden()
        }
    }
    
    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        recycledPages.removeAll()
    }
    
    // MARK: - set startap values
    
    // MARK: - setting of buttons
    // This function should be at the beginning of the other functions
    private func setCustomSetting() {
        if displayCustomCloseButton == true {
            displayCloseButton = false
        }
        if displayCustomDeleteButton == true {
            displayDeleteButton = false
        }
    }
    
    // MARK: - Buttons' setting
    // MARK: Close button
    private func setSettingCloseButton() {
        if displayCloseButton == true {
            let doneImage = UIImage(named: "SKPhotoBrowser.bundle/images/btn_common_close_wh", inBundle: bundle, compatibleWithTraitCollection: nil) ?? UIImage()
            closeButton = UIButton(type: UIButtonType.Custom)
            closeButton.setImage(doneImage, forState: UIControlState.Normal)
            if UI_USER_INTERFACE_IDIOM() == .Phone {
                closeButton.imageEdgeInsets = UIEdgeInsetsMake(15.25, 15.25, 15.25, 15.25)
            } else {
                closeButton.imageEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12)
            }
            closeButton.backgroundColor = .clearColor()
            closeButton.addTarget(self, action: "closeButtonPressed:", forControlEvents: UIControlEvents.TouchUpInside)
            closeButtonHideFrame = CGRect(x: 5, y: -20, width: 44, height: 44)
            closeButtonShowFrame = CGRect(x: 5, y: 5, width: 44, height: 44)
            view.addSubview(closeButton)
            closeButton.translatesAutoresizingMaskIntoConstraints = true
            closeButton.autoresizingMask = [.FlexibleBottomMargin, .FlexibleLeftMargin, .FlexibleRightMargin, .FlexibleTopMargin]
        }
    }
    
    // MARK: Delete button
    
    private func setSettingDeleteButton() {
        if displayDeleteButton == true {
            deleteButton = UIButton(type: .Custom)
            deleteButtonShowFrame = CGRect(x: view.frame.width - 44, y: 5, width: 44, height: 44)
            deleteButtonHideFrame = CGRect(x: view.frame.width - 44, y: -20, width: 44, height: 44)
            let image = UIImage(named: "SKPhotoBrowser.bundle/images/btn_common_delete_wh", inBundle: bundle, compatibleWithTraitCollection: nil) ?? UIImage()
            if UI_USER_INTERFACE_IDIOM() == .Phone {
                deleteButton.imageEdgeInsets = UIEdgeInsets(top: 15.25, left: 15.25, bottom: 15.25, right: 15.25)
            } else {
                deleteButton.imageEdgeInsets = UIEdgeInsetsMake(12.3, 12.3, 12.3, 12.3)
            }
            deleteButton.setImage(image, forState: .Normal)
            deleteButton.addTarget(self, action: "deleteButtonPressed:", forControlEvents: UIControlEvents.TouchUpInside)
            deleteButton.alpha = 0.0
            view.addSubview(deleteButton)
            deleteButton.translatesAutoresizingMaskIntoConstraints = true
            deleteButton.autoresizingMask = [.FlexibleBottomMargin, .FlexibleLeftMargin, .FlexibleRightMargin, .FlexibleTopMargin]
        }
    }
    
    // MARK: - Custom buttons' setting
    // MARK: Custom Close Button
    
    private func setSettingCustomCloseButton() {
        if displayCustomCloseButton == true {
            let closeImage = UIImage(named: "SKPhotoBrowser.bundle/images/btn_common_close_wh", inBundle: bundle, compatibleWithTraitCollection: nil) ?? UIImage()
            customCloseButton = UIButton(type: .Custom)
            customCloseButton.addTarget(self, action: "closeButtonPressed:", forControlEvents: .TouchUpInside)
            customCloseButton.backgroundColor = .clearColor()
            // If another developer has not set their values
            if customCloseButtonImage != nil {
                customCloseButton.setImage(customCloseButtonImage, forState: .Normal)
            } else {
                customCloseButton.setImage(closeImage, forState: .Normal)
            }
            if customCloseButtonShowFrame == nil && customCloseButtonHideFrame == nil {
                customCloseButtonShowFrame = CGRect(x: 5, y: 5, width: 44, height: 44)
                customCloseButtonHideFrame = CGRect(x: 5, y: -20, width: 44, height: 44)
            }
            if customCloseButtonEdgeInsets != nil {
                customCloseButton.imageEdgeInsets = customCloseButtonEdgeInsets
            }
            
            customCloseButton.translatesAutoresizingMaskIntoConstraints = true
            view.addSubview(customCloseButton)
            customCloseButton.autoresizingMask = [.FlexibleBottomMargin, .FlexibleLeftMargin, .FlexibleRightMargin, .FlexibleTopMargin]
            
        }
    }
    
    // MARK: Custom Delete Button
    private func setSettingCustomDeleteButton() {
        if displayCustomDeleteButton == true {
            customDeleteButton = UIButton(type: .Custom)
            customDeleteButton.backgroundColor = .clearColor()
            customDeleteButton.addTarget(self, action: "deleteButtonPressed:", forControlEvents: .TouchUpInside)
            // If another developer has not set their values
            if customDeleteButtonShowFrame == nil && customDeleteButtonHideFrame == nil {
                customDeleteButtonShowFrame = CGRect(x: view.frame.width - 44, y: 5, width: 44, height: 44)
                customDeleteButtonHideFrame = CGRect(x: view.frame.width - 44, y: -20, width: 44, height: 44)
            }
            if let _customDeleteButtonImage = customDeleteButtonImage {
                customDeleteButton.setImage(_customDeleteButtonImage, forState: .Normal)
            }
            if let _customDeleteButtonEdgeInsets = customDeleteButtonEdgeInsets {
                customDeleteButton.imageEdgeInsets = _customDeleteButtonEdgeInsets
            }
            view.addSubview(customDeleteButton)
            customDeleteButton.translatesAutoresizingMaskIntoConstraints = true
            customDeleteButton.autoresizingMask = [.FlexibleBottomMargin, .FlexibleLeftMargin, .FlexibleRightMargin, .FlexibleTopMargin]
        }
    }
    
    // MARK: - notification
    public func handleSKPhotoLoadingDidEndNotification(notification: NSNotification) {
        
        guard let photo = notification.object as? SKPhotoProtocol else {
            return
        }
        let page = pageDisplayingAtPhoto(photo)
        if page.photo == nil {
            return
        }
        if page.photo.underlyingImage != nil {
            page.displayImage()
            loadAdjacentPhotosIfNecessary(photo)
        } else {
            page.displayImageFailure()
        }
    }
    
    public func loadAdjacentPhotosIfNecessary(photo: SKPhotoProtocol) {
        let page = pageDisplayingAtPhoto(photo)
        let pageIndex = (page.tag - pageIndexTagOffset)
        if currentPageIndex == pageIndex {
            if pageIndex > 0 {
                // Preload index - 1
                let previousPhoto = photoAtIndex(pageIndex - 1)
                if previousPhoto.underlyingImage == nil {
                    previousPhoto.loadUnderlyingImageAndNotify()
                }
            }
            if pageIndex < numberOfPhotos - 1 {
                // Preload index + 1
                let nextPhoto = photoAtIndex(pageIndex + 1)
                if nextPhoto.underlyingImage == nil {
                    nextPhoto.loadUnderlyingImageAndNotify()
                }
            }
        }
    }
    
    // MARK: - initialize / setup
    public func reloadData() {
        performLayout()
        view.setNeedsLayout()
    }
    
    public func performLayout() {
        isPerformingLayout = true
        
        // for tool bar
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: self, action: nil)
        var items = [UIBarButtonItem]()
        items.append(flexSpace)
        if numberOfPhotos > 1 && displayBackAndForwardButton {
            items.append(toolPreviousButton)
        }
        if displayCounterLabel {
            items.append(flexSpace)
            items.append(toolCounterButton)
            items.append(flexSpace)
        } else {
            items.append(flexSpace)
        }
        if numberOfPhotos > 1 && displayBackAndForwardButton {
            items.append(toolNextButton)
        }
        items.append(flexSpace)
        if displayAction {
            items.append(toolActionButton)
        }
        toolBar.setItems(items, animated: false)
        updateToolbar()
        
        // reset local cache
        visiblePages.removeAll()
        recycledPages.removeAll()
        
        // set content offset
        pagingScrollView.contentOffset = contentOffsetForPageAtIndex(currentPageIndex)
        
        // tile page
        tilePages()
        didStartViewingPageAtIndex(currentPageIndex)
        
        isPerformingLayout = false
        
        // add pangesture if need
        if !disableVerticalSwipe {
            view.addGestureRecognizer(panGesture)
        }
        
    }
    
    public func prepareForClosePhotoBrowser() {
        applicationWindow.removeGestureRecognizer(panGesture)
        NSObject.cancelPreviousPerformRequestsWithTarget(self)
    }
    
    // MARK: - frame calculation
    public func frameForPagingScrollView() -> CGRect {
        var frame = view.bounds
        frame.origin.x -= 10
        frame.size.width += (2 * 10)
        return frame
    }
    
    public func frameForToolbarAtOrientation() -> CGRect {
        let currentOrientation = UIApplication.sharedApplication().statusBarOrientation
        var height: CGFloat = navigationController?.navigationBar.frame.size.height ?? 44
        if UIInterfaceOrientationIsLandscape(currentOrientation) {
            height = 32
        }
        
        return CGRect(x: 0, y: view.bounds.size.height - height, width: view.bounds.size.width, height: height)
    }
    
    public func frameForToolbarHideAtOrientation() -> CGRect {
        let currentOrientation = UIApplication.sharedApplication().statusBarOrientation
        var height: CGFloat = navigationController?.navigationBar.frame.size.height ?? 44
        if UIInterfaceOrientationIsLandscape(currentOrientation) {
            height = 32
        }
        
        return CGRect(x: 0, y: view.bounds.size.height + height, width: view.bounds.size.width, height: height)
    }
    
    public func frameForCaptionView(captionView: SKCaptionView, index: Int) -> CGRect {
        let pageFrame = frameForPageAtIndex(index)
        let captionSize = captionView.sizeThatFits(CGSize(width: pageFrame.size.width, height: 0))
        let navHeight = navigationController?.navigationBar.frame.size.height ?? 44
        
        return CGRect(x: pageFrame.origin.x, y: pageFrame.size.height - captionSize.height - navHeight,
            width: pageFrame.size.width, height: captionSize.height)
    }
    
    public func frameForPageAtIndex(index: Int) -> CGRect {
        let bounds = pagingScrollView.bounds
        var pageFrame = bounds
        pageFrame.size.width -= (2 * 10)
        pageFrame.origin.x = (bounds.size.width * CGFloat(index)) + 10
        return pageFrame
    }
    
    public func contentOffsetForPageAtIndex(index: Int) -> CGPoint {
        let pageWidth = pagingScrollView.bounds.size.width
        let newOffset = CGFloat(index) * pageWidth
        return CGPoint(x: newOffset, y: 0)
    }
    
    public func contentSizeForPagingScrollView() -> CGSize {
        let bounds = pagingScrollView.bounds
        return CGSize(width: bounds.size.width * CGFloat(numberOfPhotos), height: bounds.size.height)
    }
    
    /// This function changes buttons's frame after the rotation of the device
    private func frameForButton() {
        if displayDeleteButton == true {
            deleteButtonShowFrame = CGRect(x: view.frame.width - 44, y: 5, width: 44, height: 44)
            deleteButtonHideFrame = CGRect(x: view.frame.width - 44, y: -20, width: 44, height: 44)
        }
        if displayCustomDeleteButton == true {
            customDeleteButtonShowFrame = CGRect(x: customDeleteButtonShowFrame.origin.y, y: customDeleteButtonShowFrame.origin.x, width: customDeleteButtonShowFrame.width, height: customDeleteButtonShowFrame.height)
            customDeleteButtonHideFrame = CGRect(x: customDeleteButtonHideFrame.origin.y, y: customDeleteButtonHideFrame.origin.x, width: customDeleteButtonHideFrame.width, height: customDeleteButtonHideFrame.height)
        }
        if displayCustomCloseButton == true {
            customCloseButtonHideFrame = CGRect(x: customCloseButtonHideFrame.origin.y, y: customCloseButtonHideFrame.origin.x, width: customCloseButtonHideFrame.width, height: customCloseButtonHideFrame.height)
            customCloseButtonShowFrame = CGRect(x: customCloseButtonShowFrame.origin.y, y: customCloseButtonShowFrame.origin.x, width: customCloseButtonShowFrame.width, height: customCloseButtonShowFrame.height)
        }
    }
    
    // MARK: - delete function
    @objc private func deleteButtonPressed(sender: UIButton) {
        delegate?.removePhoto?(self, index: currentPageIndex, reload: { () -> Void in
            self.deleteImage()
        })
    }
    
    private func deleteImage() {
        if photos.count > 1 {
            photos.removeAtIndex(currentPageIndex)
            if currentPageIndex != 0 {
                gotoPreviousPage()
            }
            updateToolbar()
        } else if photos.count == 1 {
            dismissPhotoBrowser()
        }
        reloadData()
    }
    
    // MARK: - Toolbar
    public func updateToolbar() {
        if numberOfPhotos > 1 {
            toolCounterLabel.text = "\(currentPageIndex + 1) / \(numberOfPhotos)"
        } else {
            toolCounterLabel.text = nil
        }
        
        toolPreviousButton.enabled = (currentPageIndex > 0)
        toolNextButton.enabled = (currentPageIndex < numberOfPhotos - 1)
    }
    
    // MARK: - panGestureRecognized
    public func panGestureRecognized(sender: UIPanGestureRecognizer) {
        
        let scrollView = pageDisplayedAtIndex(currentPageIndex)
        
        let viewHeight = scrollView.frame.size.height
        let viewHalfHeight = viewHeight/2
        
        var translatedPoint = sender.translationInView(self.view)
        
        // gesture began
        if sender.state == .Began {
            firstX = scrollView.center.x
            firstY = scrollView.center.y
            
            senderViewForAnimation?.hidden = (currentPageIndex == initialPageIndex)
            
            isDraggingPhoto = true
            setNeedsStatusBarAppearanceUpdate()
        }
        
        translatedPoint = CGPoint(x: firstX, y: firstY + translatedPoint.y)
        scrollView.center = translatedPoint
        
        view.opaque = true
        
        // gesture end
        if sender.state == .Ended {
            if scrollView.center.y > viewHalfHeight+40 || scrollView.center.y < viewHalfHeight-40 {
                
                determineAndClose()
                return

            } else {
                
                // Continue Showing View
                isDraggingPhoto = false
                setNeedsStatusBarAppearanceUpdate()
                
                let velocityY: CGFloat = CGFloat(self.animationDuration) * sender.velocityInView(self.view).y
                let finalX: CGFloat = firstX
                let finalY: CGFloat = viewHalfHeight
                
                let animationDuration = Double(abs(velocityY) * 0.0002 + 0.2)
                
                UIView.beginAnimations(nil, context: nil)
                UIView.setAnimationDuration(animationDuration)
                UIView.setAnimationCurve(UIViewAnimationCurve.EaseIn)
                scrollView.center = CGPoint(x: finalX, y: finalY)
                UIView.commitAnimations()
            }
        }
    }
    
    // MARK: - perform animation
    public func performPresentAnimation() {
        
        view.hidden = true
        pagingScrollView.alpha = 0.0
        
        let fadeView = UIView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
        fadeView.backgroundColor = .blackColor()
        fadeView.alpha = 0.0
        applicationWindow.addSubview(fadeView)
        
        if let sender = delegate?.viewForPhoto?(self, index: initialPageIndex) ?? senderViewForAnimation {
            
            senderViewOriginalFrame = (sender.superview?.convertRect(sender.frame, toView:nil))!
            
            let imageFromView = senderOriginImage != nil ? senderOriginImage : getImageFromView(sender)
            resizableImageView = UIImageView(image: imageFromView)
            resizableImageView.frame = senderViewOriginalFrame
            resizableImageView.clipsToBounds = true
            resizableImageView.contentMode = .ScaleAspectFill
            applicationWindow.addSubview(resizableImageView)
            
            sender.hidden = true
            
            let scaleFactor = UIApplication.sharedApplication().statusBarOrientation == .Portrait
                ? imageFromView.size.width / screenWidth
                : imageFromView.size.height / screenHeight
            
            let finalImageViewFrame = CGRect(
                x: (screenWidth/2) - ((imageFromView.size.width / scaleFactor)/2),
                y: (screenHeight/2) - ((imageFromView.size.height / scaleFactor)/2),
                width: imageFromView.size.width / scaleFactor,
                height: imageFromView.size.height / scaleFactor)
            
            if sender.layer.cornerRadius != 0 {
                let duration = (animationDuration * Double(animationDamping))
                self.resizableImageView.layer.masksToBounds = true
                self.resizableImageView.addCornerRadiusAnimation(sender.layer.cornerRadius, to: 0, duration: duration)
            }
            
            UIView.animateWithDuration(animationDuration, delay:0, usingSpringWithDamping:animationDamping, initialSpringVelocity:0, options:.CurveEaseInOut, animations: { () -> Void in
                
                    fadeView.alpha = 1.0
                    self.resizableImageView.frame = finalImageViewFrame
                
                    if self.displayCloseButton == true {
                        self.closeButton.alpha = 1.0
                        self.closeButton.frame = self.closeButtonShowFrame
                    }
                    if self.displayDeleteButton == true {
                        self.deleteButton.alpha = 1.0
                        self.deleteButton.frame = self.deleteButtonShowFrame
                    }
                    if self.displayCustomCloseButton == true {
                        self.customCloseButton.alpha = 1.0
                        self.customCloseButton.frame = self.customCloseButtonShowFrame
                    }
                    if self.displayCustomDeleteButton == true {
                        self.customDeleteButton.alpha = 1.0
                        self.customDeleteButton.frame = self.customDeleteButtonShowFrame
                    }
                },
                completion: { (Bool) -> Void in
                    self.view.hidden = false
                    self.pagingScrollView.alpha = 1.0
                    self.resizableImageView.alpha = 0.0
                    fadeView.removeFromSuperview()
            })
            
        } else {
            
            UIView.animateWithDuration(animationDuration, delay:0, usingSpringWithDamping:animationDamping, initialSpringVelocity:0, options:.CurveEaseInOut, animations: { () -> Void in
                    fadeView.alpha = 1.0
                    if self.displayCloseButton == true {
                        self.closeButton.alpha = 1.0
                        self.closeButton.frame = self.closeButtonShowFrame
                    }
                    if self.displayDeleteButton == true {
                        self.deleteButton.alpha = 1.0
                        self.deleteButton.frame = self.deleteButtonShowFrame
                    }
                    if self.displayCustomCloseButton == true {
                        self.customCloseButton.alpha = 1.0
                        self.customCloseButton.frame = self.customCloseButtonShowFrame
                    }
                    if self.displayCustomDeleteButton == true {
                        self.customDeleteButton.alpha = 1.0
                        self.customDeleteButton.frame = self.customDeleteButtonShowFrame
                    }
                },
                completion: { (Bool) -> Void in
                    self.view.hidden = false
                    self.pagingScrollView.alpha = 1.0
                    fadeView.removeFromSuperview()
            })
        }
    }
    
    public func performCloseAnimationWithScrollView(scrollView: SKZoomingScrollView) {
        
        view.hidden = true
        
        if let sender = senderViewForAnimation {
            senderViewOriginalFrame = (sender.superview?.convertRect(sender.frame, toView:nil))!
        }
        
        let fadeView = UIView(frame: CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
        let contentOffset = scrollView.contentOffset
        let scrollFrame = scrollView.photoImageView.frame
        let offsetY = scrollView.center.y - (scrollView.bounds.height/2)
        
        let frame = CGRect(
            x: scrollFrame.origin.x - contentOffset.x,
            y: scrollFrame.origin.y + contentOffset.y + offsetY,
            width: scrollFrame.width,
            height: scrollFrame.height)
        
        fadeView.backgroundColor = .blackColor()
        fadeView.alpha = 1.0
        
        applicationWindow.addSubview(fadeView)
        resizableImageView.frame = frame
        resizableImageView.alpha = 1.0
        resizableImageView.clipsToBounds = true
        resizableImageView.contentMode = .ScaleAspectFill
        applicationWindow.addSubview(resizableImageView)
        
        if let view = senderViewForAnimation where view.layer.cornerRadius != 0 {
            let duration = (animationDuration * Double(animationDamping))
            self.resizableImageView.layer.masksToBounds = true
            self.resizableImageView.addCornerRadiusAnimation(0, to: view.layer.cornerRadius, duration: duration)
        }
        
        UIView.animateWithDuration(animationDuration, delay:0, usingSpringWithDamping:animationDamping, initialSpringVelocity:0, options:.CurveEaseInOut, animations: { () -> () in
                fadeView.alpha = 0.0
                self.resizableImageView.layer.frame = self.senderViewOriginalFrame
            },
            completion: { (Bool) -> () in
                self.resizableImageView.removeFromSuperview()
                fadeView.removeFromSuperview()
                self.dismissPhotoBrowser()
        })
    }
    
    public func dismissPhotoBrowser() {
        modalTransitionStyle = .CrossDissolve
        senderViewForAnimation?.hidden = false
        prepareForClosePhotoBrowser()
        dismissViewControllerAnimated(true) {
            self.delegate?.didDismissAtPageIndex?(self.currentPageIndex)
        }
    }

    private func determineAndClose() {
        
        delegate?.willDismissAtPageIndex?(currentPageIndex)
        let scrollView = pageDisplayedAtIndex(currentPageIndex)
        
        if currentPageIndex == initialPageIndex {
            performCloseAnimationWithScrollView(scrollView)
            return
        } else if let sender = delegate?.viewForPhoto?(self, index: currentPageIndex), image = photoAtIndex(currentPageIndex).underlyingImage {
            
            senderViewForAnimation = sender
            resizableImageView.image = image
            performCloseAnimationWithScrollView(scrollView)
            return
        } else {
            dismissPhotoBrowser()
        }
        
    }
    
    //MARK: - image
    private func getImageFromView(sender: UIView) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(sender.frame.size, true, 0.0)
        sender.layer.renderInContext(UIGraphicsGetCurrentContext()!)
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
    
    public func imageForPhoto(photo: SKPhotoProtocol) -> UIImage? {
        if photo.underlyingImage != nil {
            return photo.underlyingImage
        } else {
            photo.loadUnderlyingImageAndNotify()
            return nil
        }
    }
    
    // MARK: - paging
    public func initializePageIndex(index: Int) {
        var i = index
        if index >= numberOfPhotos {
            i = numberOfPhotos - 1
        }
        
        initialPageIndex = i
        currentPageIndex = i
        
        if isViewLoaded() {
            jumpToPageAtIndex(index)
            if !isViewActive {
                tilePages()
            }
        }
    }
    
    public func jumpToPageAtIndex(index: Int) {
        if index < numberOfPhotos {
            if !isEndAnimationByToolBar {
                return
            }
            isEndAnimationByToolBar = false
            let pageFrame = frameForPageAtIndex(index)
            pagingScrollView.setContentOffset(CGPoint(x: pageFrame.origin.x - 10, y: 0), animated: true)
            updateToolbar()
        }
        hideControlsAfterDelay()
    }
    
    public func photoAtIndex(index: Int) -> SKPhotoProtocol {
        return photos[index]
    }
    
    public func gotoPreviousPage() {
        jumpToPageAtIndex(currentPageIndex - 1)
    }
    
    public func gotoNextPage() {
        jumpToPageAtIndex(currentPageIndex + 1)
    }
    
    public func tilePages() {
        
        let visibleBounds = pagingScrollView.bounds
        
        var firstIndex = Int(floor((CGRectGetMinX(visibleBounds) + 10 * 2) / CGRectGetWidth(visibleBounds)))
        var lastIndex  = Int(floor((CGRectGetMaxX(visibleBounds) - 10 * 2 - 1) / CGRectGetWidth(visibleBounds)))
        if firstIndex < 0 {
            firstIndex = 0
        }
        if firstIndex > numberOfPhotos - 1 {
            firstIndex = numberOfPhotos - 1
        }
        if lastIndex < 0 {
            lastIndex = 0
        }
        if lastIndex > numberOfPhotos - 1 {
            lastIndex = numberOfPhotos - 1
        }
        
        for page in visiblePages {
            let newPageIndex = page.tag - pageIndexTagOffset
            if newPageIndex < firstIndex || newPageIndex > lastIndex {
                recycledPages.append(page)
                page.prepareForReuse()
                page.removeFromSuperview()
            }
        }
        
        let visibleSet = Set(visiblePages)
        visiblePages = Array(visibleSet.subtract(recycledPages))
        
        while (recycledPages.count > 2) {
            recycledPages.removeFirst()
        }
        
        for var index = firstIndex; index <= lastIndex; index++ {
            if isDisplayingPageForIndex(index) {
                continue
            }
            
            let page = SKZoomingScrollView(frame: view.frame, browser: self)
            page.frame = frameForPageAtIndex(index)
            page.tag = index + pageIndexTagOffset
            page.photo = photoAtIndex(index)
            
            visiblePages.append(page)
            pagingScrollView.addSubview(page)
            // if exists caption, insert
            if let captionView = captionViewForPhotoAtIndex(index) {
                captionView.frame = frameForCaptionView(captionView, index: index)
                pagingScrollView.addSubview(captionView)
                // ref val for control
                page.captionView = captionView
            }
        }
    }
    
    private func didStartViewingPageAtIndex(index: Int) {
        delegate?.didShowPhotoAtIndex?(index)
    }
    
    private func captionViewForPhotoAtIndex(index: Int) -> SKCaptionView? {
        let photo = photoAtIndex(index)
        if let _ = photo.caption {
            let captionView = SKCaptionView(photo: photo)
            captionView.alpha = areControlsHidden() ? 0.0 : 1.0
            return captionView
        }
        return nil
    }
    
    public func isDisplayingPageForIndex(index: Int) -> Bool {
        for page in visiblePages {
            if (page.tag - pageIndexTagOffset) == index {
                return true
            }
        }
        return false
    }
    
    public func pageDisplayedAtIndex(index: Int) -> SKZoomingScrollView {
        var thePage: SKZoomingScrollView = SKZoomingScrollView()
        for page in visiblePages {
            if (page.tag - pageIndexTagOffset) == index {
                thePage = page
                break
            }
        }
        return thePage
    }
    
    public func pageDisplayingAtPhoto(photo: SKPhotoProtocol) -> SKZoomingScrollView {
        var thePage: SKZoomingScrollView = SKZoomingScrollView()
        for page in visiblePages {
            if page.photo === photo {
                thePage = page
                break
            }
        }
        return thePage
    }
    
    // MARK: - Control Hiding / Showing
    public func cancelControlHiding() {
        if controlVisibilityTimer != nil {
            controlVisibilityTimer.invalidate()
            controlVisibilityTimer = nil
        }
    }
    
    public func hideControlsAfterDelay() {
        // reset
        cancelControlHiding()
        // start
        controlVisibilityTimer = NSTimer.scheduledTimerWithTimeInterval(4.0, target: self, selector: "hideControls:", userInfo: nil, repeats: false)
        
    }
    
    public func hideControls(timer: NSTimer) {
        setControlsHidden(true, animated: true, permanent: false)
    }
    
    public func toggleControls() {
        setControlsHidden(!areControlsHidden(), animated: true, permanent: false)
    }
    
    public func setControlsHidden(hidden: Bool, animated: Bool, permanent: Bool) {
        cancelControlHiding()
        var captionViews = Set<SKCaptionView>()
        for page in visiblePages {
            if page.captionView != nil {
                captionViews.insert(page.captionView)
            }
        }
        
        UIView.animateWithDuration(animationDuration,
            animations: { () -> Void in
                let alpha: CGFloat = hidden ? 0.0 : 1.0
                self.toolBar.alpha = alpha
                self.toolBar.frame = hidden ? self.frameForToolbarHideAtOrientation() : self.frameForToolbarAtOrientation()
                if self.displayCloseButton == true {
                    self.closeButton.alpha = alpha
                    self.closeButton.frame = hidden ? self.closeButtonHideFrame : self.closeButtonShowFrame
                }
                if self.displayDeleteButton == true {
                    self.deleteButton.alpha = alpha
                    self.deleteButton.frame = hidden ? self.deleteButtonHideFrame : self.deleteButtonShowFrame
                }
                if self.displayCustomCloseButton == true {
                    self.customCloseButton.alpha = alpha
                    self.customCloseButton.frame = hidden ? self.customCloseButtonHideFrame : self.customCloseButtonShowFrame
                }
                if self.displayCustomDeleteButton == true {
                    self.customDeleteButton.alpha = alpha
                    self.customDeleteButton.frame = hidden ? self.customDeleteButtonHideFrame : self.customDeleteButtonShowFrame
                }
                for v in captionViews {
                    v.alpha = alpha
                }
            },
            completion: { (Bool) -> Void in
        })
        
        if !permanent {
            hideControlsAfterDelay()
        }
        
        setNeedsStatusBarAppearanceUpdate()
    }
    
    public func areControlsHidden() -> Bool {
        return toolBar.alpha == 0.0
    }
    
    // MARK: - Button
    public func closeButtonPressed(sender: UIButton) {
        
        determineAndClose()
    }
    
    // MARK: Action Button
    public func actionButtonPressed() {
        let photo = photoAtIndex(currentPageIndex)
        
        delegate?.willShowActionSheet?(currentPageIndex)
        
        if numberOfPhotos > 0 && photo.underlyingImage != nil {
            if let titles = actionButtonTitles {
                let actionSheetController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
                actionSheetController.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: { (action) -> Void in
                }))
                for actionTitle in titles {
                    actionSheetController.addAction(UIAlertAction(title: actionTitle, style: .Default, handler: { (action) -> Void in
                        
                    }))
                }
                
                if UI_USER_INTERFACE_IDIOM() == .Phone {
                    presentViewController(actionSheetController, animated: true, completion: nil)
                } else {
                    actionSheetController.modalPresentationStyle = .Popover
                    let popoverController = actionSheetController.popoverPresentationController!
                    popoverController.barButtonItem = toolActionButton
                    presentViewController(actionSheetController, animated: true, completion: { () -> Void in
                        
                    })
                }
            } else {
                var activityItems: [AnyObject] = [photo.underlyingImage]
                if photo.caption != nil {
                    if let shareExtraCaption = shareExtraCaption {
                        activityItems.append(photo.caption + shareExtraCaption)
                    } else {
                        activityItems.append(photo.caption)
                    }
                }
                activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                activityViewController.completionWithItemsHandler = {
                    (activity, success, items, error) in
                    self.hideControlsAfterDelay()
                    self.activityViewController = nil
                }
                if UI_USER_INTERFACE_IDIOM() == .Phone {
                    presentViewController(activityViewController, animated: true, completion: nil)
                } else {
                    activityViewController.modalPresentationStyle = .Popover
                    let popover: UIPopoverPresentationController! = activityViewController.popoverPresentationController
                    popover.barButtonItem = toolActionButton
                    presentViewController(activityViewController, animated: true, completion: nil)
                }
            }
        }
        
    }
    
    // MARK: -  UIScrollView Delegate
    public func scrollViewDidScroll(scrollView: UIScrollView) {
        guard isViewActive else {
            return
        }
        guard !isPerformingLayout else {
            return
        }
        
        // tile page
        tilePages()
        
        // Calculate current page
        let visibleBounds = pagingScrollView.bounds
        var index = Int(floor(CGRectGetMidX(visibleBounds) / CGRectGetWidth(visibleBounds)))
        
        if index < 0 {
            index = 0
        }
        if index > numberOfPhotos - 1 {
            index = numberOfPhotos
        }
        let previousCurrentPage = currentPageIndex
        currentPageIndex = index
        if currentPageIndex != previousCurrentPage {
            didStartViewingPageAtIndex(currentPageIndex)
            updateToolbar()
        }
    }
    
    public func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        setControlsHidden(true, animated: true, permanent: false)
    }
    
    public func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        hideControlsAfterDelay()
    }
    
    public func scrollViewDidEndScrollingAnimation(scrollView: UIScrollView) {
        isEndAnimationByToolBar = true
    }
}

extension UIView
{
    func addCornerRadiusAnimation(from: CGFloat, to: CGFloat, duration: CFTimeInterval)
    {
        let animation = CABasicAnimation(keyPath:"cornerRadius")
        animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        self.layer.addAnimation(animation, forKey: "cornerRadius")
        self.layer.cornerRadius = to
    }
}
