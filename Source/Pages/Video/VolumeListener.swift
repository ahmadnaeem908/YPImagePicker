//
//  File.swift
//  YPImagePicker
//
//  Created by Ahmad naeem on 5/20/21.
//
 
import UIKit
import Combine
import MediaPlayer

class VolumeListener {
    
    static let shared = VolumeListener()
     
    var initailVolume : Float?
    var volumeCancellable: AnyCancellable?
    var didBecomeActiveCancellable: AnyCancellable?
    var didResignCancellable: AnyCancellable?
    var volumeView : MPVolumeView?
 
    var completion : ((_ volume: Float) -> Void)?
    
    func add(containerView : UIView,callback : @escaping (_   volume : Float) -> Void){
        completion = callback
        let mpVolumeView = MPVolumeView(frame: CGRect(x: -CGFloat.greatestFiniteMagnitude, y: 0, width: 0, height: 0))
        containerView.addSubview(mpVolumeView  )
        
        volumeView = mpVolumeView
        initailVolume = AVAudioSession.sharedInstance().outputVolume
        addVolumeListener()
        addAppStateListener()
    }
    
    func addVolumeListener(){
       let volumeViewSlider = volumeView?.subviews.first { $0 is UISlider } as? UISlider
        initailVolume = AVAudioSession.sharedInstance().outputVolume
        
        var lastDate = Date()
        var skip = false
        volumeCancellable = NotificationCenter.default
            .publisher(for: Self.kSystemVolumeDidChangeNotificationName)
            .compactMap({ not -> Float? in
                if let volume = not.userInfo?[Self.kAudioVolumeNotificationParameter] as? Float,
                   let changeReason = not.userInfo?[Self.kAudioVolumeChangeReasonNotificationParameter] as? String,
                   changeReason == Self.kExplicitVolumeChange{
                    return volume
                }else{
                    return nil
                }
            })
            .sink(receiveValue: {[weak self] (volume) in
                
             
                // Do whatever you'd like here
                let currentDate = Date()
                let diff = currentDate-lastDate
             
                lastDate = currentDate
               
                
                let diffInt = Int(diff*100)
                
                if diffInt >= 1 {
                    print("123^ = " ,volume)
                    print("123# time diff =" , diff)
                    DispatchQueue.main.async {
                        self?.completion?(volume)
                    }
                }
                
                if self?.initailVolume == volume {
                    return
                }
//
                let updatedVolume = self?.initailVolume
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
                    if let updatedVolume = updatedVolume {
                        volumeViewSlider?.value = updatedVolume
                    }
                }
//                DispatchQueue.main.async {
//                    if let updatedVolume = updatedVolume {
//                        volumeViewSlider?.value = updatedVolume
//                    }
//                }
            })
    }
    /*
     for every volome that is not 0 and 1 , the every inital == volume will not be callback
     for the value 0 and 1, we will have a
     */
    func addAppStateListener(){
        if didBecomeActiveCancellable != nil {
            return
        }
        didBecomeActiveCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] noti in
                print("didBecomeActiveNotification")
                self?.addVolumeListener()
            }
        didResignCancellable = NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] noti in
                self?.removeVolumeListener()
            }
        
    }
    
    func removeVolumeListener(){
        volumeCancellable?.cancel()
        volumeCancellable = nil
    }
    
    func remove() {
        removeVolumeListener()
        didBecomeActiveCancellable?.cancel()
        didResignCancellable?.cancel()
        volumeView?.removeFromSuperview()
        didBecomeActiveCancellable = nil
        didResignCancellable = nil
        volumeView = nil
        completion = nil
        initailVolume = nil
    }
    
    deinit {
        remove()
    }
    
    static let kAudioVolumeChangeReasonNotificationParameter = "AVSystemController_AudioVolumeChangeReasonNotificationParameter"
    static let kAudioVolumeNotificationParameter = "AVSystemController_AudioVolumeNotificationParameter"
    static let kExplicitVolumeChange = "ExplicitVolumeChange"
    static let kSystemVolumeDidChangeNotificationName = NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification")
}
extension Date {

    static func - (lhs: Date, rhs: Date) -> TimeInterval {
        return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }
    
}
