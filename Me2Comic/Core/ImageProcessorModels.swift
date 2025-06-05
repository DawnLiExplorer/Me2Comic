//
//  ImageProcessorModels.swift
//  Me2Comic
//
//  Created by me2 on 2025/6/5.
//

import Foundation

struct ProcessingParameters {
    let widthThreshold: String
    let resizeHeight: String
    let quality: String
    let threadCount: Int
    let unsharpRadius: String
    let unsharpSigma: String
    let unsharpAmount: String
    let unsharpThreshold: String
    let batchSize: String
    let useGrayColorspace: Bool
}

/// Manages a processing task with a unique ID
struct ManagedTask: Identifiable {
    let id = UUID()
    let process: Process
}

