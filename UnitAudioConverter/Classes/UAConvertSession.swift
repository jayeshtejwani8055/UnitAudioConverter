//
//  UAConvertSession.swift
//  UnitAudioConverter
//
//  Created by Quang Tran on 6/29/21.
//

import AVFoundation

public class UAConvertSession {
    let id: UUID = UUID()
    
    var avExportSession: AVAssetExportSession?
    var workItem: DispatchWorkItem?
    var mp3Converter: ExtAudioConverter?
    
    var isCancelled = false
    var state = MutableState()

    private var pendingCompletionError: Error?
    private var hasPendingCompletion = false
    
    var timer: Timer?
    
    func timer(timeInterval: TimeInterval, block: @escaping ((Timer) -> Void) ) {
        timer = Timer(timeInterval: timeInterval, repeats: true, block: block)
        timer?.fire()
    }
    
    public func cancel() {
        avExportSession?.cancelExport()
        workItem?.cancel()
        mp3Converter = nil
        isCancelled = true
        UAConverter.shared.finish(session: self, error: UAConverter.ConvertError.cancelled)
    }
    
    deinit {
        timer?.invalidate()
    }
    
    //Method to be implemented latter
    @discardableResult
    private func progress(_ block: @escaping UAConvertProgressBlock) -> Self {
        state.progressBlock = block
        return self
    }
    
    @discardableResult
    public func completion(_ block: @escaping UAConvertCompletionBlock) -> Self {
        state.completionBlock = block

        if hasPendingCompletion {
            hasPendingCompletion = false
            let error = pendingCompletionError
            pendingCompletionError = nil

            block(error)
        }

        return self
    }

    func complete(error: Error?) {
        if let completionBlock = state.completionBlock {
            completionBlock(error)
        } else {
            pendingCompletionError = error
            hasPendingCompletion = true
        }
    }
}

extension UAConvertSession {
    struct MutableState {
        var progressBlock: UAConvertProgressBlock?
        var completionBlock: UAConvertCompletionBlock?
    }
}

extension UAConvertSession: Hashable {
    public static func == (lhs: UAConvertSession, rhs: UAConvertSession) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
}
