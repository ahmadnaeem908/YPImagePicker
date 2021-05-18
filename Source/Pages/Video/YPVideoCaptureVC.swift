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
    
    // MARK: - Init
    
    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public required init() {
        super.init(nibName: nil, bundle: nil)
        title = YPConfig.wordings.videoTitle
        videoHelper.didCaptureVideo = { [weak self] videoURL in
            self?.didCaptureVideo?(videoURL)
            self?.resetVisualState()
        }
        
        videoHelper.didCapturePhoto = { [weak self] image in
            self?.didCapturePhoto?(image)
            let i = image
            print(i)
//            self?.resetVisualState()
        }
//        self.didCapturePhoto{ image in
//            let i = image
//            print(image)
//        }
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
        
        videoHelper.shoot { imageData in
            
            guard let shotImage = UIImage(data: imageData) else {
                return
            }
            
            self.stopCamera()
            
            var image = shotImage
            // Crop the image if the output needs to be square.
//            if YPConfig.onlySquareImagesFromCamera {
//                image = self.cropImageToSquare(image)
//            }

            // Flip image if taken form the front camera.
            if let device = self.videoHelper.device, device.position == .front {
                image = flipImage(image: image)
            }
            
            DispatchQueue.main.async {
                let noOrietationImage = image.resetOrientation()
                let capturedImage = noOrietationImage
                print(capturedImage)
                self.didCapturePhoto?(noOrietationImage )
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
    var volumeButtonHandler : VolumeButtonHandler!
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        v.timeElapsedLabel.isHidden = false // Show the time elapsed label since we're in the video screen.
        setupButtons()
        linkButtons()
        
        // Focus
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        v.previewViewContainer.addGestureRecognizer(tapRecognizer)
        
        // Zoom
        let pinchRecongizer = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch(_:)))
        v.previewViewContainer.addGestureRecognizer(pinchRecongizer)
        
        self.volumeButtonHandler = VolumeButtonHandler(containerView: self.view)
        volumeButtonHandler.buttonClosure = {[weak self] button in
            // ...
            self?.volumeButtonControlls(button:button)
            
        }
        volumeButtonHandler.start()
        /*
         so here we will use
         a timer we will call shoot after 0.2 sec and if the volume is 0
         if volume is 1 then we will start the recording and add timer that will stop the recording after 0.2 sec
         also need to have button so if it is up and then we get dwon we will stop every thing
         */
    }
    func volumeButtonControlls(button: VolumeButtonHandler.Button){
        photoTimer?.invalidate()
        if volumeButtonTapped == nil{
            volumeButtonTapped = button
        }
//        else if  volumeButtonTapped != button,videoTimer != nil{
////            videoTimer?.invalidate()
//            print("123# stop recording ")
//            return
//        }
        // ...
//        switch button {
//
//        case .up:
//
//         let t =   Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { (_) in
//
//            }
//            volumeTap += 1
//        case .down:
//            volumeTap -= 1
//        }
//        photoTimer?.invalidate()
        if volumeTap == 0 {
            print("123# photoTimer")
            photoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) {[weak self] (_) in
                print("123# take photo")
                
                self?.doAfterPermissionCheck {
                    if self?.volumeTap == 1 {
                        self?.shoot()
                    }
                    
                }
            }
        }
//        else if volumeTap > 1 {
//            print("123# start recording ")
//            if videoTimer == nil {
//                self.videoHelper.setupCaptureSession()
//                print("123# video long press  began" )
//                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { (_) in
//
//                    self.doAfterPermissionCheck { [weak self] in
//                        self?.toggleRecording()
//                    }
//                }
//            }
//            videoTimer?.invalidate()
//            videoTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {[weak self] (_) in
//                print("123# stop recording ")
//                self?.doAfterPermissionCheck {
//                    self?.toggleRecording()
//                }
//            }
//        }
//        let currentDate = Date()
//        print("123# time diff =" , currentDate-lastDate)
//        lastDate = currentDate
           volumeTap += 1
    }
    var lastDate : Date = Date()
    var volumeButtonTapped : VolumeButtonHandler.Button!
    var photoTimer: Timer!
    var videoTimer: Timer!
    
var volumeTap = 0
    
    func start() {
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
        
        let longGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        v.shotButton.addGestureRecognizer(longGesture)
    }
    
    @objc func handleLongPress(gestureReconizer: UILongPressGestureRecognizer) {
        if gestureReconizer.state ==  .began {
            
            print("video long press  began" )
            self.doAfterPermissionCheck { [weak self] in
                self?.toggleRecording()
            }
            
        }  else if  gestureReconizer.state ==  .ended  {
            //When lognpress is finish
            if  videoHelper.isRecording == false{
                
            }else{
                doAfterPermissionCheck { [weak self] in
                    self?.toggleRecording()
                }
                print("video long press  ended" )
            }
            
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

    public func stopCamera() {
        videoHelper.stopCamera()
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
        v.shotButton.setImage(state.isRecording ? YPConfig.icons.captureVideoOnImage : YPConfig.icons.captureVideoImage,
                              for: .normal)
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
}

extension Date {

    static func - (lhs: Date, rhs: Date) -> TimeInterval {
        return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }

}
