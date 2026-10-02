//
//  UAConverter.swift
//  UnitAudioConverter
//
//  Created by Quang Tran on 6/29/21.
//

import Foundation
import AVFoundation
import AudioToolbox

public typealias UAConvertProgressBlock = (Float) -> Void
public typealias UAConvertCompletionBlock = (Error?) -> Void

public class UAConverter {
    public static let shared = UAConverter()
    
    var activeSessions: Set<UAConvertSession> = []
    // Thêm các queue riêng biệt cho từng loại xử lý
    private let audioProcessingQueue = DispatchQueue(label: "com.uaconverter.processing", qos: .utility)
    
    private init() {
        
    }

    @discardableResult
    public func convert(source: URL, destination: URL, outputType:UAFileType, completion: @escaping UAConvertCompletionBlock) -> UAConvertSession {
        // Không nén
        let session = UAConvertSession()
        session.state.completionBlock = completion
        let _ = UAConverter.convertToM4a(fileURL: source) { convertUrl in
            if outputType == .mp3 {
                let converter = ExtAudioConverter()
                session.mp3Converter = converter
                converter.outputFile = destination.path
                converter.inputFile = (convertUrl ?? source).path
                converter.outputFormatID = UAFileType.mp3.audioFormatID
                converter.outputFileType = UAFileType.mp3.audioFileTypeID
                let workItem = DispatchWorkItem {
                    do {
                        let success = session.mp3Converter?.convert()
                        if success == true, session.isCancelled == false {
                            self.finish(session: session, error: nil)
                        } else {
                            self.finish(session: session, error: session.isCancelled ? ConvertError.cancelled : ConvertError.cannotConvert)
                        }
                    } catch {
                        debugPrint("workItem convert: \(error)")
                        self.finish(session: session, error: error)
                    }
                }
                self.audioProcessingQueue.async(execute: workItem)
                session.workItem = workItem
            } else {
                let workItem = DispatchWorkItem {
                    if self.checkAudioFileAccessibility(fileURL: convertUrl ?? source) {
                        debugPrint("checkAudioFileAccessibility: \(convertUrl ?? source)")
                    }
                    try? FileManager.default.removeItem(at: destination)
                    self.convertAudio(inputURL: convertUrl ?? source, outputURL: destination, audioType: outputType.audioFileTypeID, audioFormat: outputType.audioFormatID) { outputURL, error in
                        if let url = outputURL {
                            print("Conversion Complete!")
                            self.finish(session: session, error: nil)
                        } else {
                            print("Error during convertion \(error)")
                            self.finish(session: session, error: session.isCancelled ? ConvertError.cancelled : ConvertError.cannotConvert)
                        }
                    }
                }
                self.audioProcessingQueue.async(execute: workItem)
                session.workItem = workItem
            }
        }
        activeSessions.insert(session)
        return session
    }
    
    func finish(session: UAConvertSession, error: Error?) {
        session.complete(error: error)
        activeSessions.remove(session)
    }
}

extension UAConverter {
    public enum ConvertError: Error {
        case notCompatible
        case cannotConvert
        case cancelled
    }
}

extension UAConverter {
    // Kiểm tra xem file có phải là video không
    private static func isVideoFile(fileURL: URL) -> Bool {
        let asset = AVAsset(url: fileURL)
        // Kiểm tra xem tài nguyên có chứa track video không
        let videoTracks = asset.tracks(withMediaType: .video)
        return !videoTracks.isEmpty
    }
    
    func checkAudioFileAccessibility(fileURL: URL) -> Bool {
        let asset = AVAsset(url: fileURL)
        return asset.isPlayable
    }
    
    // Nếu file là video, chuyển đổi sang m4a
    // nếu file là audio, trả về file gốc
    // nếu không phải video hoặc audio, trả về nil
    @discardableResult
    public static func convertToM4a(fileURL: URL, completion: @escaping ((URL?) -> Void)) -> AVAssetExportSession? {
        guard isVideoFile(fileURL: fileURL) == true else { completion(fileURL); return nil }
        
        let tmp_name = fileURL.deletingPathExtension().appendingPathExtension("m4a").lastPathComponent
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(tmp_name)
        try? FileManager.default.removeItem(at: tempURL)
        
        return convertToType(source: fileURL, destination: tempURL, outputFileType: .m4a, presetName: AVAssetExportPresetAppleM4A) { url in
            completion(url)
        }
    }
    
    public static func convertToType(source: URL, destination: URL, outputFileType:AVFileType, presetName: String = AVAssetExportPresetPassthrough, completion: @escaping ((URL?) -> Void)) -> AVAssetExportSession? {
        guard let exportSession = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: presetName) else {
            completion(nil)
            return nil
        }
        let dispatchGroup = DispatchGroup()
        var isCompatible = false
        // Kiểm tra tính tương thích trước khi tiếp tục
        dispatchGroup.enter()
        exportSession.determineCompatibleFileTypes { compatibleTypes in
            isCompatible = compatibleTypes.contains(where: { $0 == outputFileType})
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
        if !isCompatible {
            print("Format not compatible.")
            completion(nil)
            return nil
        }
        try? FileManager.default.removeItem(at: destination)
        exportSession.outputURL = destination
        exportSession.outputFileType = outputFileType
        exportSession.exportAsynchronously {
            if let error = exportSession.error {
                debugPrint("convertToType Error: \(error)");
                completion(nil)
            } else {
                completion(destination)
            }
        }
        return exportSession
    }

    /*
     // WAV CAF AU AAC ALAC FLAC AIFF AIFC
     
        AAC (Advanced Audio Coding)
        Định dạng đích: kAudioFormatMPEG4AAC
        Định dạng tệp: kAudioFileM4AType, kAudioFileAAC_ADTSType, kAudioFileAAC_ADTSType

        ALAC (Apple Lossless Audio Codec)
        Định dạng đích: kAudioFormatAppleLossless
        Định dạng tệp: kAudioFileM4AType

        FLAC (Free Lossless Audio Codec)
        Định dạng đích: kAudioFormatFLAC
        Định dạng tệp: kAudioFileFLACType

        AIFF (Audio Interchange File Format)
        Định dạng đích: kAudioFormatLinearPCM
        Định dạng tệp: kAudioFileAIFFType

        AIFC (Audio Interchange File Compressed)
        Định dạng đích: kAudioFormatAppleIMA4
        Định dạng tệp: kAudioFileAIFCType

        Linear PCM (Pulse Code Modulation)
        Định dạng đích: kAudioFormatLinearPCM
        Định dạng tệp: kAudioFileWAVEType, kAudioFileCAFType, kAudioFileAIFFType
        
        Chi tiết các định dạng:
        AAC (Advanced Audio Coding)
        Định dạng đích: kAudioFormatMPEG4AAC
        Định dạng tệp: kAudioFileM4AType, kAudioFileAAC_ADTSType, kAudioFileAAC_ADTSType
        Các thuộc tính:
        mSampleRate: Tốc độ mẫu của tệp nguồn
        mFormatID: kAudioFormatMPEG4AAC
        mChannelsPerFrame: Số kênh của tệp nguồn
        mFramesPerPacket: 1024
        mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue)

        ALAC (Apple Lossless Audio Codec)
        Định dạng đích: kAudioFormatAppleLossless
        Định dạng tệp: kAudioFileM4AType
        Các thuộc tính:
        mSampleRate: Tốc độ mẫu của tệp nguồn
        mFormatID: kAudioFormatAppleLossless
        mChannelsPerFrame: Số kênh của tệp nguồn
        mFramesPerPacket: 4096
        mFormatFlags: 0

        FLAC (Free Lossless Audio Codec)
        Định dạng đích: kAudioFormatFLAC
        Định dạng tệp: kAudioFileFLACType
        Các thuộc tính:
        mSampleRate: Tốc độ mẫu của tệp nguồn
        mFormatID: kAudioFormatFLAC
        mChannelsPerFrame: Số kênh của tệp nguồn
        mBitsPerChannel: 16
        mBytesPerPacket: 0 (biến đổi)
        mBytesPerFrame: 0 (biến đổi)
        mFramesPerPacket: 0 (biến đổi)
        mFormatFlags: 0

        AIFF (Audio Interchange File Format)
        Định dạng đích: kAudioFormatLinearPCM
        Định dạng tệp: kAudioFileAIFFType
        Các thuộc tính:
        mSampleRate: Tốc độ mẫu của tệp nguồn
        mFormatID: kAudioFormatLinearPCM
        mChannelsPerFrame: Số kênh của tệp nguồn
        mBitsPerChannel: 16
        mBytesPerPacket: 2 * mChannelsPerFrame
        mBytesPerFrame: 2 * mChannelsPerFrame
        mFramesPerPacket: 1
        mFormatFlags: kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsBigEndian

        AIFC (Audio Interchange File Compressed)
        Định dạng đích: kAudioFormatAppleIMA4
        Định dạng tệp: kAudioFileAIFCType
        Các thuộc tính:
        mSampleRate: Tốc độ mẫu của tệp nguồn
        mFormatID: kAudioFormatAppleIMA4
        mChannelsPerFrame: Số kênh của tệp nguồn
        mBitsPerChannel: 16
        mBytesPerPacket: 34
        mBytesPerFrame: 2
        mFramesPerPacket: 64
        mFormatFlags: 0

        Linear PCM (Pulse Code Modulation)
        Định dạng đích: kAudioFormatLinearPCM
        Định dạng tệp: kAudioFileWAVEType, kAudioFileCAFType, kAudioFileAIFFType
        Các thuộc tính:
        mSampleRate: 44100
        mFormatID: audioFormat
        mChannelsPerFrame: Số kênh của tệp nguồn
        mBitsPerChannel: 16
        mBytesPerPacket: 2 * mChannelsPerFrame
        mBytesPerFrame: 2 * mChannelsPerFrame
        mFramesPerPacket: 1
        mFormatFlags: kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger
    */
    func convertAudio(inputURL: URL, outputURL: URL, audioType: AudioFileTypeID, audioFormat: AudioFormatID, progress: UAConvertProgressBlock? = nil, completion: @escaping ((URL?, Error?) -> Void)) {

        var destinationFile: ExtAudioFileRef? = nil
        var sourceFile: ExtAudioFileRef? = nil

        // Định nghĩa hàm xử lý lỗi
        let handleError = { (status: OSStatus, operation: String) -> Error? in
            guard status != noErr else { return nil }
            return NSError(domain: "UAConverter",
                          code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Lỗi \(operation): \(status)"])
        }
        print("About to open \(inputURL) which has a status of \(FileManager.default.fileExists(atPath: inputURL.path)) which looks like this: \(inputURL as CFURL) as a CFURL")
        
        // 1. Mở file nguồn
        var status = ExtAudioFileOpenURL(inputURL as CFURL, &sourceFile)
        if let error = handleError(status, "mở file nguồn") {
            completion(nil, error)
            return
        }
        // Đảm bảo resources được giải phóng khi hàm kết thúc
        defer {
            if let sourceFile = sourceFile {
                ExtAudioFileDispose(sourceFile)
            }
            if let destinationFile = destinationFile {
                ExtAudioFileDispose(destinationFile)
            }
        }
        print("Opened source file")
        // 2. Lấy thông tin định dạng nguồn
        var srcFormat = AudioStreamBasicDescription()
        var propSize = UInt32(MemoryLayout.stride(ofValue: srcFormat))
        status = ExtAudioFileGetProperty(sourceFile!,
                                       kExtAudioFileProperty_FileDataFormat,
                                       &propSize, &srcFormat)
        if let error = handleError(status, "đọc định dạng nguồn") {
            DispatchQueue.main.async { completion(nil, error) }
            return
        }
        
        // 3. Thiết lập định dạng đích dựa vào loại audio
        var dstFormat = self.createDestinationFormat(sourceFormat: srcFormat,
                                                    targetFormat: audioFormat,
                                                    audioType: audioType)
        // 4. Tạo file đích
        try? FileManager.default.removeItem(at: outputURL)
        status = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            audioType,
            &dstFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &destinationFile)
        
        if let error = handleError(status, "tạo file đích") {
            DispatchQueue.main.async { completion(nil, error) }
            return
        }
        
        // 5. Thiết lập định dạng client (định dạng cho xử lý trung gian)
        var clientFormat = self.createClientFormat(sourceFormat: srcFormat)
        
        // Áp dụng định dạng client cho cả file nguồn và đích
        status = ExtAudioFileSetProperty(sourceFile!,
                                       kExtAudioFileProperty_ClientDataFormat,
                                       UInt32(MemoryLayout.size(ofValue: clientFormat)),
                                       &clientFormat)
        
        if let error = handleError(status, "thiết lập định dạng client cho nguồn") {
            DispatchQueue.main.async { completion(nil, error) }
            return
        }
        
        status = ExtAudioFileSetProperty(destinationFile!,
                                       kExtAudioFileProperty_ClientDataFormat,
                                       UInt32(MemoryLayout.size(ofValue: clientFormat)),
                                       &clientFormat)
        
        if let error = handleError(status, "thiết lập định dạng client cho đích") {
            DispatchQueue.main.async { completion(nil, error) }
            return
        }
        
        // 6. Tính toán kích thước buffer tối ưu (64KB là chuẩn tốt cho hiệu suất IO)
        let bufferByteSize: UInt32 = 65536
        let bufferFrameSize = bufferByteSize / clientFormat.mBytesPerFrame
        var totalFrames: Int64 = 0
        var processedFrames: Int64 = 0
        // Lấy tổng số frames để tính tiến độ
        var fileLengthInFrames: Int64 = 0
        var sizeOfProperty = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(sourceFile!,
                              kExtAudioFileProperty_FileLengthFrames,
                              &sizeOfProperty,
                              &fileLengthInFrames)
        
        totalFrames = fileLengthInFrames
        
        // 7. Tiến hành chuyển đổi
        var srcBuffer = [Float](repeating: 0, count: Int(bufferByteSize))
        
        while true {
            // Cập nhật tiến độ mỗi 10 lần đọc
            if let progressHandler = progress, totalFrames > 0, processedFrames % (10 * Int64(bufferFrameSize)) == 0 {
                let progressValue = Float(processedFrames) / Float(max(1, totalFrames))
                DispatchQueue.main.async {
                    progressHandler(progressValue)
                }
            }
            
            // Thiết lập buffer để đọc
            var fillBufList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: clientFormat.mChannelsPerFrame,
                    mDataByteSize: bufferByteSize,
                    mData: &srcBuffer
                )
            )
            
            // Đọc frames từ file nguồn
            var numFrames = bufferFrameSize
            status = ExtAudioFileRead(sourceFile!, &numFrames, &fillBufList)
            
            if let error = handleError(status, "đọc dữ liệu") {
                DispatchQueue.main.async { completion(nil, error) }
                return
            }
            
            // Nếu không còn frames nào để đọc, kết thúc
            if numFrames == 0 {
                break
            }
            
            // Cập nhật số frames đã xử lý
            processedFrames += Int64(numFrames)
            
            // Ghi dữ liệu vào file đích
            status = ExtAudioFileWrite(destinationFile!, numFrames, &fillBufList)
            
            if let error = handleError(status, "ghi dữ liệu") {
                DispatchQueue.main.async { completion(nil, error) }
                return
            }
        }
        
        // Báo hoàn thành
        completion(outputURL, nil)
    }
    
    // Hàm hỗ trợ tạo định dạng đích
    private func createDestinationFormat(sourceFormat: AudioStreamBasicDescription,
                                        targetFormat: AudioFormatID,
                                        audioType: AudioFileTypeID) -> AudioStreamBasicDescription {
        
        var dstFormat = AudioStreamBasicDescription()
        
        switch (targetFormat, audioType) {
        case (kAudioFormatMPEG4AAC, _):
            dstFormat.mSampleRate = sourceFormat.mSampleRate
            dstFormat.mFormatID = kAudioFormatMPEG4AAC
            dstFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
            dstFormat.mFramesPerPacket = 1024
            dstFormat.mFormatFlags = AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue)
            
        case (kAudioFormatAppleLossless, _):
            dstFormat.mSampleRate = sourceFormat.mSampleRate
            dstFormat.mFormatID = kAudioFormatAppleLossless
            dstFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
            dstFormat.mFramesPerPacket = 4096
            dstFormat.mFormatFlags = 0
            
        case (kAudioFormatFLAC, _):
            dstFormat.mSampleRate = sourceFormat.mSampleRate
            dstFormat.mFormatID = kAudioFormatFLAC
            dstFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
            dstFormat.mBitsPerChannel = 16
            dstFormat.mFormatFlags = 0
            
        case (kAudioFormatLinearPCM, kAudioFileAIFFType):
            dstFormat.mSampleRate = sourceFormat.mSampleRate
            dstFormat.mFormatID = kAudioFormatLinearPCM
            dstFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
            dstFormat.mBitsPerChannel = 16
            dstFormat.mBytesPerPacket = 2 * sourceFormat.mChannelsPerFrame
            dstFormat.mBytesPerFrame = 2 * sourceFormat.mChannelsPerFrame
            dstFormat.mFramesPerPacket = 1
            dstFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsBigEndian
            
        case (kAudioFormatAppleIMA4, kAudioFileAIFCType):
            dstFormat.mSampleRate = sourceFormat.mSampleRate
            dstFormat.mFormatID = kAudioFormatAppleIMA4
            dstFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
            dstFormat.mBitsPerChannel = 16
            dstFormat.mBytesPerPacket = 34
            dstFormat.mBytesPerFrame = 2
            dstFormat.mFramesPerPacket = 64
            dstFormat.mFormatFlags = 0
            
        default:
            // Định dạng mặc định cho các trường hợp khác
            dstFormat.mSampleRate = 44100
            dstFormat.mFormatID = targetFormat
            dstFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
            dstFormat.mBitsPerChannel = 16
            dstFormat.mBytesPerPacket = 2 * sourceFormat.mChannelsPerFrame
            dstFormat.mBytesPerFrame = 2 * sourceFormat.mChannelsPerFrame
            dstFormat.mFramesPerPacket = 1
            dstFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger
        }
        
        return dstFormat
    }

    // Hàm tạo định dạng client cho xử lý trung gian
    private func createClientFormat(sourceFormat: AudioStreamBasicDescription) -> AudioStreamBasicDescription {
        return AudioStreamBasicDescription(
            mSampleRate: sourceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * sourceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * sourceFormat.mChannelsPerFrame,
            mChannelsPerFrame: sourceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }
}
