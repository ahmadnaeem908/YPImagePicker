//
//  YPVideoHelper.swift
//  YPImagePicker
//
//  Created by Sacha DSO on 27/01/2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMotion

extension  YPVideoCaptureHelper :  YPPhotoCapture, AVCapturePhotoCaptureDelegate{
    func tryToggleFlash() {
        // if device.hasFlash device.isFlashAvailable //TODO test these
        switch currentFlashMode {
        case .auto:
            currentFlashMode = .on
        case .on:
            currentFlashMode = .off
        case .off:
            currentFlashMode = .auto
        }
    }
    
    var hasFlash: Bool {
        guard let device = device else { return false }
        return device.hasFlash
    }
     
    func shoot(completion: @escaping (Data) -> Void) {
        block = completion
        setCurrentOrienation()
        let settings = newSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @available(iOS 11.0, *)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        block?(data)
    }
        
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
                     previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     bracketSettings: AVCaptureBracketedStillImageSettings?,
                     error: Error?) {
        guard let buffer = photoSampleBuffer else { return }
        if let data = AVCapturePhotoOutput
            .jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer,
                                         previewPhotoSampleBuffer: previewPhotoSampleBuffer) {
            block?(data)
        }
    }
    
     
    var device: AVCaptureDevice? { return deviceInput?.device }
    var output: AVCaptureOutput { return photoOutput }
    
    
    func configure() {
        photoOutput.isHighResolutionCaptureEnabled = true
        
        // Improve capture time by preparing output with the desired settings.
        photoOutput.setPreparedPhotoSettingsArray([newSettings()], completionHandler: nil)
        
    }
    
    private func newSettings() -> AVCapturePhotoSettings {
        var settings = AVCapturePhotoSettings()
        
        // Catpure Heif when available.
        if #available(iOS 11.0, *) {
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
        }
        
        // Catpure Highest Quality possible.
        settings.isHighResolutionPhotoEnabled = true
        
        // Set flash mode.
        if let deviceInput = deviceInput {
            if deviceInput.device.isFlashAvailable {
                switch currentTorchMode() {
                case .auto:
                    if photoOutput.__supportedFlashModes.contains(NSNumber(value: AVCaptureDevice.FlashMode.auto.rawValue)) {
                        settings.flashMode = .auto
                    }
                case .off:
                    if photoOutput.__supportedFlashModes.contains(NSNumber(value: AVCaptureDevice.FlashMode.off.rawValue)) {
                        settings.flashMode = .off
                    }
                case .on:
                    if photoOutput.__supportedFlashModes.contains(NSNumber(value: AVCaptureDevice.FlashMode.on.rawValue)) {
                        settings.flashMode = .on
                    }
                @unknown default:
                    fatalError("currentTorchMode in correct")
                }
            }
        }
        return settings
    }
}

/// Abstracts Low Level AVFoudation details.
class YPVideoCaptureHelper: NSObject {
    ///Image
    
    var currentFlashMode: YPFlashMode = .off
    var videoLayer: AVCaptureVideoPreviewLayer!
    private let photoOutput = AVCapturePhotoOutput()
    var deviceInput: AVCaptureDeviceInput?
    var block: ((Data) -> Void)?
    public var didCapturePhoto: ((UIImage) -> Void)?
    ///////
    public var isRecording: Bool { return videoOutput.isRecording }
    public var didCaptureVideo: ((URL) -> Void)?
    public var videoRecordingProgress: ((Float, TimeInterval) -> Void)?
    
    var session = AVCaptureSession()
    internal let sessionPhoto = AVCaptureSession()
    private var timer = Timer()
    private var dateVideoStarted = Date()
    internal let sessionQueue = DispatchQueue(label: "YPVideoVCSerialQueue")
    private (set) var videoInput: AVCaptureDeviceInput?
    private var videoOutput = AVCaptureMovieFileOutput()
    private var videoRecordingTimeLimit: TimeInterval = 0
    internal var isCaptureSessionSetup: Bool = false
    internal var isPreviewSetup = false
    internal var previewView: UIView!
    private var motionManager = CMMotionManager()
    internal var initVideoZoomFactor: CGFloat = 1.0
    
    // MARK: - Init
    
    public func start(previewView: UIView, withVideoRecordingLimit: TimeInterval, completion: @escaping () -> Void) {
        self.previewView = previewView
        self.videoRecordingTimeLimit = withVideoRecordingLimit
        sessionQueue.async { [weak self] in
            guard let strongSelf = self else {
                return
            }
            if !strongSelf.isCaptureSessionSetup {
                strongSelf.setupCaptureSession()
//                strongSelf.setupPhotoCaptureSession()
            }
            strongSelf.startCamera(completion: {
                completion()
            })
        }
    }
    
    // MARK: - Start Camera
    
    public func startCamera(completion: @escaping (() -> Void)) {
        if !session.isRunning {
            sessionQueue.async { [weak self] in
                // Re-apply session preset
                self?.session.sessionPreset = .high
                let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
                switch status {
                case .notDetermined, .restricted, .denied:
                    self?.session.stopRunning()
                case .authorized:
                    self?.session.startRunning()
                    completion()
                    self?.tryToSetupPreview()
                @unknown default:
                    fatalError()
                }
            }
        }
        if !sessionPhoto.isRunning {
            sessionQueue.async { [weak self] in
                // Re-apply session preset
                self?.sessionPhoto.sessionPreset = .photo
                let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
                switch status {
                case .notDetermined, .restricted, .denied:
                    self?.sessionPhoto.stopRunning()
                case .authorized:
                    self?.sessionPhoto.startRunning()
                    completion()
                    self?.tryToSetupPreview()
                @unknown default:
                    fatalError()
                }
            }
        }
    }
    
    // MARK: - Flip Camera
    
    public func flipCamera(completion: @escaping () -> Void) {
        sessionQueue.async { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.session.beginConfiguration()
            strongSelf.session.resetInputs()
            
            if let videoInput = strongSelf.videoInput {
                strongSelf.videoInput = flippedDeviceInputForInput(videoInput)
            }
            
            if let videoInput = strongSelf.videoInput {
                if strongSelf.session.canAddInput(videoInput) {
                    strongSelf.session.addInput(videoInput)
                }
            }
            
            // Re Add audio recording
            for device in AVCaptureDevice.devices(for: .audio) {
                if let audioInput = try? AVCaptureDeviceInput(device: device) {
                    if strongSelf.session.canAddInput(audioInput) {
                        strongSelf.session.addInput(audioInput)
                    }
                }
            }
            strongSelf.session.commitConfiguration()
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    // MARK: - Focus
    
    public func focus(onPoint point: CGPoint) {
        if let device = videoInput?.device {
            setFocusPointOnDevice(device: device, point: point)
        }
    }
    
    // MARK: - Zoom
    
    public func zoom(began: Bool, scale: CGFloat) {
        guard let device = videoInput?.device else {
            return
        }

        if began {
            initVideoZoomFactor = device.videoZoomFactor
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            var minAvailableVideoZoomFactor: CGFloat = 1.0
            if #available(iOS 11.0, *) {
                minAvailableVideoZoomFactor = device.minAvailableVideoZoomFactor
            }
            var maxAvailableVideoZoomFactor: CGFloat = device.activeFormat.videoMaxZoomFactor
            if #available(iOS 11.0, *) {
                maxAvailableVideoZoomFactor = device.maxAvailableVideoZoomFactor
            }
            maxAvailableVideoZoomFactor = min(maxAvailableVideoZoomFactor, YPConfig.maxCameraZoomFactor)

            let desiredZoomFactor = initVideoZoomFactor * scale
            device.videoZoomFactor = max(minAvailableVideoZoomFactor,
                                         min(desiredZoomFactor, maxAvailableVideoZoomFactor))
        } catch let error {
            print("💩 \(error)")
        }
    }
    
    // MARK: - Stop Camera
    
    public func stopCamera() {
        if session.isRunning {
            sessionQueue.async { [weak self] in
                self?.session.stopRunning()
            }
        }
        if sessionPhoto.isRunning {
            sessionQueue.async { [weak self] in
                self?.sessionPhoto.stopRunning()
            }
        }
    }
    
    // MARK: - Torch
    
    public func hasTorch() -> Bool {
        return videoInput?.device.hasTorch ?? false
    }
    
    public func currentTorchMode() -> AVCaptureDevice.TorchMode {
        guard let device = videoInput?.device else {
            return .off
        }
        if !device.hasTorch {
            return .off
        }
        return device.torchMode
    }
    
    public func toggleTorch() {
        videoInput?.device.tryToggleTorch()
    }
    
    // MARK: - Recording
    
    public func startRecording() {
        
        let outputURL = YPVideoProcessor.makeVideoPathURL(temporaryFolder: true, fileName: "recordedVideoRAW")

        checkOrientation { [weak self] orientation in
            guard let strongSelf = self else {
                return
            }
            if let connection = strongSelf.videoOutput.connection(with: .video) {
                if let orientation = orientation, connection.isVideoOrientationSupported {
                    connection.videoOrientation = orientation
                }
                strongSelf.videoOutput.startRecording(to: outputURL, recordingDelegate: strongSelf)
            }
        }
    }
    
    public func stopRecording() {
        videoOutput.stopRecording()
    }
    
    // Private
   func getDetupCaptureSession() -> AVCaptureSession {
        let session = AVCaptureSession()
        session.beginConfiguration()
        let aDevice = deviceForPosition(.back)
        if let d = aDevice {
            videoInput = try? AVCaptureDeviceInput(device: d)
        }
        
        if let videoInput = videoInput {
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            // Add audio recording
            for device in AVCaptureDevice.devices(for: .audio) {
                if let audioInput = try? AVCaptureDeviceInput(device: device) {
                    if session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                    }
                }
            }
            
            let timeScale: Int32 = 30 // FPS
            let maxDuration =
                CMTimeMakeWithSeconds(self.videoRecordingTimeLimit, preferredTimescale: timeScale)
            videoOutput.maxRecordedDuration = maxDuration
            if let sizeLimit = YPConfig.video.recordingSizeLimit {
                videoOutput.maxRecordedFileSize = sizeLimit
            }
            videoOutput.minFreeDiskSpaceLimit = YPConfig.video.minFreeDiskSpaceLimit
            if YPConfig.video.fileType == .mp4,
               YPConfig.video.recordingSizeLimit != nil {
                videoOutput.movieFragmentInterval = .invalid // Allows audio for MP4s over 10 seconds.
            }
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            session.sessionPreset = .high
        }
        session.commitConfiguration()
        isCaptureSessionSetup = true
    return session
    }
      func setupCaptureSession() {
        session.beginConfiguration()
       
        let aDevice = deviceForPosition(.back)
        if let d = aDevice {
            videoInput = try? AVCaptureDeviceInput(device: d)
            deviceInput = try? AVCaptureDeviceInput(device: d)
        }
        
        if let videoInput = deviceInput {
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
                configure()
            }
            session.sessionPreset = .photo
        }
        
        if let videoInput = videoInput {
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            // Add audio recording
            for device in AVCaptureDevice.devices(for: .audio) {
                if let audioInput = try? AVCaptureDeviceInput(device: device) {
                    if session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                    }
                }
            }
            
            let timeScale: Int32 = 30 // FPS
            let maxDuration =
                CMTimeMakeWithSeconds(self.videoRecordingTimeLimit, preferredTimescale: timeScale)
            videoOutput.maxRecordedDuration = maxDuration
            if let sizeLimit = YPConfig.video.recordingSizeLimit {
                videoOutput.maxRecordedFileSize = sizeLimit
            }
            videoOutput.minFreeDiskSpaceLimit = YPConfig.video.minFreeDiskSpaceLimit
            if YPConfig.video.fileType == .mp4,
               YPConfig.video.recordingSizeLimit != nil {
                videoOutput.movieFragmentInterval = .invalid // Allows audio for MP4s over 10 seconds.
            }
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            session.sessionPreset = .high
        }
        session.commitConfiguration()
        isCaptureSessionSetup = true
    }
    
    // MARK: - Recording Progress
    
    @objc
    func tick() {
        let timeElapsed = Date().timeIntervalSince(dateVideoStarted)
        var progress: Float
        if let recordingSizeLimit = YPConfig.video.recordingSizeLimit {
            progress = Float(videoOutput.recordedFileSize) / Float(recordingSizeLimit)
        } else {
            progress = Float(timeElapsed) / Float(videoRecordingTimeLimit)
        }
        // VideoOutput configuration is responsible for stopping the recording. Not here.
        DispatchQueue.main.async {
            self.videoRecordingProgress?(progress, timeElapsed)
        }
    }
    
    // MARK: - Orientation

    /// This enables to get the correct orientation even when the device is locked for orientation \o/
    private func checkOrientation(completion: @escaping(_ orientation: AVCaptureVideoOrientation?) -> Void) {
        motionManager.accelerometerUpdateInterval = 5
        motionManager.startAccelerometerUpdates( to: OperationQueue() ) { [weak self] data, _ in
            self?.motionManager.stopAccelerometerUpdates()
            guard let data = data else {
                completion(nil)
                return
            }
            let orientation: AVCaptureVideoOrientation = abs(data.acceleration.y) < abs(data.acceleration.x)
                ? data.acceleration.x > 0 ? .landscapeLeft : .landscapeRight
                : data.acceleration.y > 0 ? .portraitUpsideDown : .portrait
            DispatchQueue.main.async {
                completion(orientation)
            }
        }
    }

    // MARK: - Preview
    
    func tryToSetupPreview() {
        if !isPreviewSetup {
            setupPreview()
            isPreviewSetup = true
        }
    }
    
    func setupPreview() {
        let videoLayer = AVCaptureVideoPreviewLayer(session: session)
        DispatchQueue.main.async {
            videoLayer.frame = self.previewView.bounds
            videoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            self.previewView.layer.addSublayer(videoLayer)
        }
    }
}

extension YPVideoCaptureHelper: AVCaptureFileOutputRecordingDelegate {
    
    public func fileOutput(_ captureOutput: AVCaptureFileOutput,
                           didStartRecordingTo fileURL: URL,
                           from connections: [AVCaptureConnection]) {
        timer = Timer.scheduledTimer(timeInterval: 1,
                                     target: self,
                                     selector: #selector(tick),
                                     userInfo: nil,
                                     repeats: true)
        dateVideoStarted = Date()
    }
    
    public func fileOutput(_ captureOutput: AVCaptureFileOutput,
                           didFinishRecordingTo outputFileURL: URL,
                           from connections: [AVCaptureConnection],
                           error: Error?) {
        if let error = error {
            print(error)
        }
       
        
        let flipVideoIfFrontCamera : (_ outputFileURL: URL) -> Void = { [weak self] outputFileURL in
            if self?.videoInput?.device.position == .front{
                YPVideoProcessor.mirrorVideo(inputURL: outputFileURL) {[weak self] url in
                    if let url = url {
                        self?.sendVideoBackInClouser(url)
                    }
                }
            }else{
                self?.sendVideoBackInClouser(outputFileURL)
            }
        }
        /**/
        if YPConfig.onlySquareImagesFromCamera {
            YPVideoProcessor.cropToSquare(filePath: outputFileURL) { url in
                guard let url = url else { return }
                flipVideoIfFrontCamera(url)
            }
        } else {
            flipVideoIfFrontCamera(outputFileURL)
        }
        
        timer.invalidate()
    }
   
        
    private func sendVideoBackInClouser (_ url : URL)  {
        let resolution =  resolutionForLocalVideo(url: url)!
        let resolutionRatio = resolution.width / resolution.height
        let screenRatio = UIScreen.width / UIScreen.height
        
        if !resolutionRatio.isEqual(to: screenRatio, tilFloatingPoints: 3){
            let newResolutionWidth  = (screenRatio*resolution.height)
            let newCalculatedSize = CGSize(width: newResolutionWidth, height: resolution.height)
            let widthDifference = resolution.width - newResolutionWidth

            print("resolution ,", resolution)
            print("screenRatio ", screenRatio)
            print("resolutionRatio ",resolutionRatio)
            print("newResolutionWidth , =", newResolutionWidth)
            print("newSize , =", newCalculatedSize)
            print("widthDifference , =", widthDifference)

            YPVideoProcessor.cropTo(newSize: newCalculatedSize, url, widthDifference: widthDifference) {[weak self] newURL in
                if let newURL = newURL{
                    self?.didCaptureVideo?(newURL)
                }else{
                    self?.didCaptureVideo?(url)
                }
            }
        }else{
            didCaptureVideo?(url)
        }
    }
    
    private func resolutionForLocalVideo(url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return nil }
       let size = track.naturalSize.applying(track.preferredTransform)
       return CGSize(width: abs(size.width), height: abs(size.height))
    }
}
extension  CGFloat {
    func isEqual(to other : CGFloat,tilFloatingPoints num: Int) -> Bool{
        var points : CGFloat = 1.0
        for _ in 0..<num{ points *= 10  }
     return Int(self*points) == Int(other*points)
    }
}

extension UIScreen {
 static var width : CGFloat {
      return UIScreen.main.bounds.width
  }
 static var height : CGFloat {
      return UIScreen.main.bounds.height
  }
}
 
