//
//  YPVideoProcessor.swift
//  YPImagePicker
//
//  Created by Nik Kov on 13.09.2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation

/*
 This class contains all support and helper methods to process the videos
 */
public class YPVideoProcessor {
    /// Creates an output path and removes the file in temp folder if existing
    ///
    /// - Parameters:
    ///   - temporaryFolder: Save to the temporary folder or somewhere else like documents folder
    ///   - suffix: the file name wothout extension
    static func makeVideoPathURL(temporaryFolder: Bool, fileName: String) -> URL {
        var outputURL: URL
        
        if temporaryFolder {
            let outputPath = "\(NSTemporaryDirectory())\(fileName).\(YPConfig.video.fileType.fileExtension)"
            outputURL = URL(fileURLWithPath: outputPath)
        } else {
            guard let documentsURL = FileManager
                .default
                .urls(for: .documentDirectory,
                      in: .userDomainMask).first else {
                        print("YPVideoProcessor -> Can't get the documents directory URL")
                return URL(fileURLWithPath: "Error")
            }
            outputURL = documentsURL.appendingPathComponent("\(fileName).\(YPConfig.video.fileType.fileExtension)")
        }
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(atPath: outputURL.path)
            } catch {
                print("YPVideoProcessor -> Can't remove the file for some reason.")
            }
        }
        
        return outputURL
    }
    
    /*
     Crops the video to square by video height from the top of the video.
     */
    static func cropToSquare(filePath: URL, completion: @escaping (_ outputURL: URL?) -> Void) {
        
        // output file
        let outputPath = makeVideoPathURL(temporaryFolder: true, fileName: "squaredVideoFromCamera")
        
        // input file
        let asset = AVAsset.init(url: filePath)
        let composition = AVMutableComposition.init()
        composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        // Prevent crash if tracks is empty
        guard asset.tracks.isEmpty == false,
              let clipVideoTrack = asset.tracks(withMediaType: .video).first else {
            return
        }
        
        // make it square
        let videoComposition = AVMutableVideoComposition()
        if YPConfig.onlySquareImagesFromCamera {
            videoComposition.renderSize = CGSize(width: CGFloat(clipVideoTrack.naturalSize.height),
                                                 height: CGFloat(clipVideoTrack.naturalSize.height))
        } else {
            videoComposition.renderSize = CGSize(width: CGFloat(clipVideoTrack.naturalSize.height),
                                                 height: CGFloat(clipVideoTrack.naturalSize.width))
        }
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)
        
        // rotate to potrait
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
        let t1 = CGAffineTransform(translationX: clipVideoTrack.naturalSize.height,
                                   y: -(clipVideoTrack.naturalSize.width - clipVideoTrack.naturalSize.height) / 2)
        let t2: CGAffineTransform = t1.rotated(by: .pi/2)
        let finalTransform: CGAffineTransform = t2
        transformer.setTransform(finalTransform, at: CMTime.zero)
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
        // exporter
        _ = asset.export(to: outputPath, videoComposition: videoComposition, removeOldFile: true) { exportSession in
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(outputPath)
                case .failed:
                    print("YPVideoProcessor Export of the video failed: \(String(describing: exportSession.error))")
                    completion(nil)
                default:
                    print("YPVideoProcessor Export session completed with \(exportSession.status) status. Not handled.")
                    completion(nil)
                }
            }
        }
    }
     
    static func mirrorVideo(inputURL: URL, completion: @escaping (_ outputURL : URL?) -> ()) {
        let videoAsset: AVAsset = AVAsset( url: inputURL )
        guard let clipVideoTrack = videoAsset.tracks( withMediaType: AVMediaType.video ).first else {
            completion(nil)
            return
        }

        let composition = AVMutableComposition()
        composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: CMPersistentTrackID())

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: clipVideoTrack.naturalSize.height, height: clipVideoTrack.naturalSize.width)
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)

        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: CMTimeMakeWithSeconds(60, preferredTimescale: 30))
        var transform:CGAffineTransform = CGAffineTransform(scaleX: -1.0, y: 1.0)
        transform = transform.translatedBy(x: -clipVideoTrack.naturalSize.width, y: 0.0)
        transform = transform.rotated(by: CGFloat(Double.pi/2))
        transform = transform.translatedBy(x: 0.0, y: -clipVideoTrack.naturalSize.width)

        transformer.setTransform(transform, at: CMTime.zero)

        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]

        // Export

        guard  let exportSession = AVAssetExportSession(asset: videoAsset, presetName: AVAssetExportPresetHighestQuality) else{
            completion(nil)
            return
        }
         
        let filePath = makeVideoPathURL(temporaryFolder: true, fileName: "mirrorVideoFromFrontCamera")

        let croppedOutputFileUrl = filePath
        exportSession.outputURL = croppedOutputFileUrl
        exportSession.outputFileType = AVFileType.mov
        exportSession.videoComposition = videoComposition
        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                DispatchQueue.main.async(execute: {
                    completion(croppedOutputFileUrl)
                })
                return
            } else if exportSession.status == .failed {
                print("Export failed - \(String(describing: exportSession.error))")
            }

            completion(nil)
            return
        }
    }
    
    public static func cropTo(newSize : CGSize,_ filePath: URL,widthDifference : CGFloat, completion: @escaping (_ outputURL: URL?) -> Void) {
        
        // output file
        let outputPath = makeVideoPathURL(temporaryFolder: true, fileName: "squaredVideoFromCamera")
        
        // input file
        let asset = AVAsset.init(url: filePath)
        let composition = AVMutableComposition.init()
        composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        // Prevent crash if tracks is empty
        guard asset.tracks.isEmpty == false,
              let clipVideoTrack = asset.tracks(withMediaType: .video).first else {
            return
        }
        
        
        let videoComposition = AVMutableVideoComposition()
        
        //       videoComposition.renderSize = CGSize(width:  naturalSizeHeight , height: naturalSizeWidth )
        //    print("clipVideoTrack.naturalSize , ", clipVideoTrack.naturalSize)
        //    print("clipVideoTrack.naturalSize width , ", clipVideoTrack.naturalSize.width)
        //    print("clipVideoTrack.naturalSize height , ", clipVideoTrack.naturalSize.height)
        
        //   videoComposition.renderSize = CGSize(width: CGFloat(clipVideoTrack.naturalSize.width),
        //                                        height: CGFloat(clipVideoTrack.naturalSize.height))
        videoComposition.renderSize  = newSize //CGSize(width: newSize.height,  height: newSize.width)
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)
        
        // rotate to potrait
        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
        var transform = CGAffineTransform(translationX: clipVideoTrack.naturalSize.height, y: 0)
            transform = transform.rotated(by: .pi/2)
         
        let finalTransform =  transform.translatedBy(x: -(widthDifference/2) , y: 0 )
        transformer.setTransform(finalTransform, at: CMTime.zero)
        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]
        
//        // exporter
//        _ = asset.export(to: outputPath, videoComposition: videoComposition, removeOldFile: true) { exportSession in
//            DispatchQueue.main.async {
//                switch exportSession.status {
//                case .completed:
//                    completion(outputPath)
//                case .failed:
//                    print("YPVideoProcessor Export of the video failed: \(String(describing: exportSession.error))")
//                    completion(nil)
//                default:
//                    print("YPVideoProcessor Export session completed with \(exportSession.status) status. Not handled.")
//                    completion(nil)
//                }
//            }
//        }
        guard  let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else{
            completion(nil)
            return
        }
         
        let filePath = makeVideoPathURL(temporaryFolder: true, fileName: "mirrorVideoFromFrontCamera")

        let croppedOutputFileUrl = filePath
        exportSession.outputURL = croppedOutputFileUrl
        exportSession.outputFileType = AVFileType.mov
        exportSession.videoComposition = videoComposition
        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                DispatchQueue.main.async(execute: {
                    completion(croppedOutputFileUrl)
                })
                return
            } else if exportSession.status == .failed {
                print("Export failed - \(String(describing: exportSession.error))")
            }

            completion(nil)
            return
        }
    }
  
}
