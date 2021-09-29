//
//  YPVideoVC.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit

public class YPVideoCaptureVC: UIViewController, YPPermissionCheckable {
    
    public var didCaptureVideo: ((URL) -> Void)?
    public var didCapturePhoto: ((UIImage) -> Void)?
    private let videoHelper = YPVideoCaptureHelper()
    private let v = YPCameraView(overlayView: nil)
    private var viewState = ViewState()
    private var activityView: UIActivityIndicatorView?
    
    // MARK: - Init
    
    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public required init() {
        super.init(nibName: nil, bundle: nil)
        title = YPConfig.wordings.videoTitle
        videoHelper.didCaptureVideo = { [weak self] videoURL in
            self?.hideActivityIndicator()
            self?.didCaptureVideo?(videoURL)
            self?.resetVisualState()
        }
        
        videoHelper.didCapturePhoto = { [weak self] image in
            self?.didCapturePhoto?(image)
//            self?.resetVisualState()
        }
        videoHelper.videoRecordingProgress = { [weak self] progress, timeElapsed in
            self?.updateState {
                $0.progress = progress
                $0.timeElapsed = timeElapsed
            }
        }
    }
    
    func shoot() {
        // Prevent from tapping multiple times in a row
        // causing a crash
//        videoHelper.setupPhotoCaptureSession()
        v.shotButton.isEnabled = false
        
        videoHelper.shoot {[weak self] imageData in
            
            guard let shotImage = UIImage(data: imageData) else {
                return
            }
            
            self?.stopCamera()
            
            var image = shotImage
            // Crop the image if the output needs to be square.
//            if YPConfig.onlySquareImagesFromCamera {
//                image = self.cropImageToSquare(image)
//            }

            // Flip image if taken form the front camera.
            if let device = self?.videoHelper.videoInput?.device, device.position == .front {
                image = flipImage(image: image)
            }
            
            DispatchQueue.main.async {
                let noOrietationImage = image.resetOrientation()
                let capturedImage = noOrietationImage
                print(capturedImage)
                self?.didCapturePhoto?(noOrietationImage )
            }
        }
        func flipImage(image: UIImage!) -> UIImage! {
            let imageSize: CGSize = image.size
            UIGraphicsBeginImageContextWithOptions(imageSize, true, 1.0)
            let ctx = UIGraphicsGetCurrentContext()!
            ctx.rotate(by: CGFloat(Double.pi/2.0))
            ctx.translateBy(x: 0, y: -imageSize.width)
            ctx.scaleBy(x: imageSize.height/imageSize.width, y: imageSize.width/imageSize.height)
            ctx.draw(image.cgImage!, in: CGRect(x: 0.0,
                                                y: 0.0,
                                                width: imageSize.width,
                                                height: imageSize.height))
            let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            return newImage
        }
    }
    // MARK: - View LifeCycle
    
    override public func loadView() { view = v }
  
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        v.timeElapsedLabel.isHidden = false // Show the time elapsed label since we're in the video screen.
        setupButtons()
        linkButtons()
        
        // Focus
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        v.previewViewContainer.addGestureRecognizer(tapRecognizer)
        
        // Zoom
        let pinchRecongizer = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch(_:)))
        v.previewViewContainer.addGestureRecognizer(pinchRecongizer)
    }
    
   
    func start() {
//        startVolumeListener()
        v.shotButton.isEnabled = false
        doAfterPermissionCheck { [weak self] in
            guard let strongSelf = self else {
                return
            }
            self?.videoHelper.start(previewView: strongSelf.v.previewViewContainer,
                                    withVideoRecordingLimit: YPConfig.video.recordingTimeLimit,
                                    completion: {
                                        DispatchQueue.main.async {
                                            self?.v.shotButton.isEnabled = true
                                            self?.refreshState()
                                        }
            })
        }
    }
    
    
    public func stopCamera() {
//        stopVolumeListener()
        videoHelper.stopCamera()
    }
    
    func refreshState() {
        // Init view state with video helper's state
        updateState {
            $0.isRecording = self.videoHelper.isRecording
            $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
        }
    }
    
    // MARK: - Setup
    
    private func setupButtons() {
        v.flashButton.setImage(YPConfig.icons.flashOffIcon, for: .normal)
        v.flipButton.setImage(YPConfig.icons.loopIcon, for: .normal)
        v.shotButton.setImage(YPConfig.icons.captureVideoImage, for: .normal)
    }
    
    private func linkButtons() {
        v.flashButton.addTarget(self, action: #selector(flashButtonTapped), for: .touchUpInside)
        v.shotButton.addTarget(self, action: #selector(shotButtonTapped), for: .touchUpInside)
        v.flipButton.addTarget(self, action: #selector(flipButtonTapped), for: .touchUpInside)
        v.dismissButton.addTarget(self, action: #selector(dismissVC), for: .touchUpInside)
        
        let longGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        v.shotButton.addGestureRecognizer(longGesture)
    }
    
    @objc
    func dismissVC() {
        self.navigationController?.dismiss(animated: true)
    }
    @objc func handleLongPress(gestureReconizer: UILongPressGestureRecognizer) {
        guard activityView == nil else { return  }
        
        if gestureReconizer.state ==  .began {
            hideActivityIndicator()
            print("video long press  began" )
            self.doAfterPermissionCheck { [weak self] in
                self?.startRecording()
            }
            
        }  else if  gestureReconizer.state ==  .ended  {
            //When lognpress is finish
            if  videoHelper.isRecording == false{
                  doAfterPermissionCheck {[weak self] in
                    self?.shoot()
                }
            }else{
                showActivityIndicator()
                doAfterPermissionCheck { [weak self] in
                    self?.stopRecording()
                }
                print("video long press  ended" )
            }
            
        }
        
    }
    // MARK: -  Camera ActivityIndicator
    func showActivityIndicator() {
      let  activityView = UIActivityIndicatorView(style: .large)
        activityView.color = YPConfig.colors.cameraVideoActivityIndicatorColor
        activityView.center = CGPoint(x: UIScreen.width/2, y:  (UIScreen.height/2)-20)
        self.view.addSubview(activityView)
        self.view.bringSubviewToFront(activityView)
        activityView.startAnimating()
        self.activityView = activityView
    }

    func hideActivityIndicator(){
        if (activityView != nil){
            activityView?.stopAnimating()
            activityView = nil
        }
    }
    // MARK: - Flip Camera
    
    @objc
    func flipButtonTapped() {
        doAfterPermissionCheck { [weak self] in
            self?.flip()
        }
    }
    
    private func flip() {
        videoHelper.flipCamera {
            self.updateState {
                $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
            }
        }
    }
    
    // MARK: - Toggle Flash
    
    @objc
    func flashButtonTapped() {
        videoHelper.toggleTorch()
        updateState {
            $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
        }
    }
    
    // MARK: - Toggle Recording
    
    @objc
    func shotButtonTapped() {
        guard activityView == nil else { return  }
//        doAfterPermissionCheck { [weak self] in
//            self?.toggleRecording()
//        }
        doAfterPermissionCheck { [weak self] in
            self?.shoot()
        }
    }
    
    private func toggleRecording() {
        videoHelper.isRecording ? stopRecording() : startRecording()
    }
    
    private func startRecording() {
        /// Stop the screen from going to sleep while recording video
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        
        videoHelper.startRecording()
        updateState {
            $0.isRecording = true
        }
    }
    
    private func stopRecording() {
        /// Reset screen always on to false since the need no longer exists
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        
        videoHelper.stopRecording()
        updateState {
            $0.isRecording = false
        }
    }

    
    // MARK: - Focus
    
    @objc
    func focusTapped(_ recognizer: UITapGestureRecognizer) {
        doAfterPermissionCheck { [weak self] in
            self?.focus(recognizer: recognizer)
        }
    }
    
    private func focus(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: v.previewViewContainer)
        let viewsize = v.previewViewContainer.bounds.size
        let newPoint = CGPoint(x: point.x/viewsize.width, y: point.y/viewsize.height)
        videoHelper.focus(onPoint: newPoint)
        v.focusView.center = point
        YPHelper.configureFocusView(v.focusView)
        v.addSubview(v.focusView)
        YPHelper.animateFocusView(v.focusView)
    }
    
    // MARK: - Zoom
    
    @objc
    func pinch(_ recognizer: UIPinchGestureRecognizer) {
        doAfterPermissionCheck { [weak self] in
            self?.zoom(recognizer: recognizer)
        }
    }
    
    func zoom(recognizer: UIPinchGestureRecognizer) {
        videoHelper.zoom(began: recognizer.state == .began, scale: recognizer.scale)
    }
    
    // MARK: - UI State
    
    enum FlashMode {
        case noFlash
        case off
        case on
        case auto
    }
    
    struct ViewState {
        var isRecording = false
        var flashMode = FlashMode.noFlash
        var progress: Float = 0
        var timeElapsed: TimeInterval = 0
    }
    
    private func updateState(block:(inout ViewState) -> Void) {
        block(&viewState)
        updateUIWith(state: viewState)
    }
    
    var circleView  : UIView!
    

    private func updateUIWith(state: ViewState) {
        func flashImage(for torchMode: FlashMode) -> UIImage {
            switch torchMode {
            case .noFlash: return UIImage()
            case .on: return YPConfig.icons.flashOnIcon
            case .off: return YPConfig.icons.flashOffIcon
            case .auto: return YPConfig.icons.flashAutoIcon
            }
        }
        v.flashButton.setImage(flashImage(for: state.flashMode), for: .normal)
        v.flashButton.isEnabled = !state.isRecording
        v.flashButton.isHidden = state.flashMode == .noFlash
        
       
        if circleView == nil {
            let size = v.shotButton.frame.size
            circleView = UIView(frame  : CGRect(x: 0, y: 0, width:  (size.width/2)-5, height:  (size.height/2)-5 ) )
            circleView.center = CGPoint(x: size.width / 2,
                                        y: size.height / 2)
            circleView.backgroundColor = #colorLiteral(red: 0.7647058824, green: 0, blue: 1, alpha: 1)
            circleView.layer.cornerRadius = ((size.width/2)-5)/2
            circleView.isUserInteractionEnabled = false
            v.shotButton.addSubview(circleView)
            v.shotButton.sendSubviewToBack(circleView)
        }
         
            if state.isRecording {
                UIView.animate(withDuration: 0.5, animations:{[weak self] in
                    let scaleVal : CGFloat = 2.2
                    self?.circleView?.transform = CGAffineTransform(scaleX: scaleVal, y: scaleVal)
                    } )
            }else{
                UIView.animate(withDuration: 0.5, animations: {[weak self] in
                    self?.circleView?.transform = .identity
                })
            }
        
        v.flipButton.isEnabled = !state.isRecording
        v.progressBar.progress = state.progress
        v.timeElapsedLabel.text = YPHelper.formattedStrigFrom(state.timeElapsed)
        
        // Animate progress bar changes.
        UIView.animate(withDuration: 1, animations: v.progressBar.layoutIfNeeded)
    }
    
    private func resetVisualState() {
        updateState {
            $0.isRecording = self.videoHelper.isRecording
            $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
            $0.progress = 0
            $0.timeElapsed = 0
        }
    }
    
    private func flashModeFrom(videoHelper: YPVideoCaptureHelper) -> FlashMode {
        if videoHelper.hasTorch() {
            switch videoHelper.currentTorchMode() {
            case .off: return .off
            case .on: return .on
            case .auto: return .auto
            @unknown default:
                fatalError()
            }
        } else {
            return .noFlash
        }
    }
    
    deinit{
        print("YPVideoCaptureVC deinit called")
    }
    
    var photoTimer: Timer!
    var videoTimer: Timer!
    var volumeTap = 0
}

extension YPVideoCaptureVC {
    
    func startVolumeListener() {
        VolumeListener.shared.add(containerView: self.view) {[weak self] volume in
            self?.volumeTapped(volume : volume)
        }
    }
    //when we remove the volume listener we will also re set the related vars
    func volumeTapped(volume : Float) {
        
        var didStopVideoCalled = false
        
        if volumeTap == 0 {
            v.shotButton.isUserInteractionEnabled = false
            photoTimer?.invalidate()
            
            var havePermission = false
            self.doAfterPermissionCheck { [weak self] in
                havePermission = true
                //                self?.toggleRecording()
                if !didStopVideoCalled {
                    self?.startRecording()
                }
                print("345@ start video 0")
            }
            
            photoTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) {[weak self] (timer) in
                if havePermission {
                    self?.shoot()
                }else{
                    self?.doAfterPermissionCheck {
                        self?.shoot()
                    }
                }
                timer.invalidate()
            }
           
            
        }else if volumeTap > 0 {
            rescheduledVideoTimer()
            if photoTimer?.isValid == true{
                photoTimer?.invalidate()
            }
          
        }
        
        func rescheduledVideoTimer() {
            print("345@ start video timer")
            videoTimer?.invalidate()
            
            videoTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) {[weak self] (timer) in
                    print("345@ stop video isRecording = ",self?.videoHelper.isRecording ?? false)
                if self?.videoHelper.isRecording == true{
                    self?.stopRecording()
                }else{
                    self?.doAfterPermissionCheck {
                        self?.shoot()
                    }
                }
                
                didStopVideoCalled = true
                print("stop video")
                timer.invalidate()
            }
        }
        
        volumeTap += 1
    }
    
    func stopVolumeListener() {
        VolumeListener.shared.remove()
        volumeTap = 0
        photoTimer?.invalidate()
        videoTimer?.invalidate()
        photoTimer = nil
        videoTimer = nil
        v.shotButton.isUserInteractionEnabled = true
    }
}
 
