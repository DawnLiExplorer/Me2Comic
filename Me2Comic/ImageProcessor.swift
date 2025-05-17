//
//  ImageProcessor.swift
//  Me2Comic
//
//  Created by Me2 on 2025/5/12.
//

import Combine
import Foundation
import UserNotifications

struct ProcessingParameters {
    let widthThreshold: String
    let resizeHeight: String
    let quality: String
    let threadCount: Int
    let unsharpRadius: String
    let unsharpSigma: String
    let unsharpAmount: String
    let unsharpThreshold: String
    let useGrayColorspace: Bool
}

/// Manages a processing task with a unique ID
struct ManagedTask: Identifiable {
    let id = UUID()
    let process: Process
}

class ImageProcessor: ObservableObject {
    private var gmPath: String = ""
    private var activeTasks: [ManagedTask] = []
    private let activeTasksQueue = DispatchQueue(label: "me2.comic.me2comic.activeTasks")
    private var shouldCancelProcessing: Bool = false // Cancellation flag
    private var totalImagesProcessed: Int = 0 // Progress counter
    private var processingStartTime: Date?

    // Log messages and processing status
    @Published var isProcessing: Bool = false
    @Published var logMessages: [String] = [] { // limited to 100 entries
        didSet {
            if logMessages.count > 100 {
                logMessages.removeFirst(logMessages.count - 100)
            }
        }
    }

    // Detect GraphicsMagick executable path
    private func detectGMPathViaWhich() -> String? {
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["gm"]

        var env = ProcessInfo.processInfo.environment
        let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"] // MacPorts？
        let originalPath = env["PATH"] ?? ""
        env["PATH"] = homebrewPaths.joined(separator: ":") + ":" + originalPath
        whichTask.environment = env

        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = pipe

        do {
            try whichTask.run()
            whichTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard whichTask.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty
            else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                logMessages.append(String(format: NSLocalizedString("WhichGMException", comment: ""), errorMessage))
                return nil
            }
            return output
        } catch {
            logMessages.append(NSLocalizedString("WhichGMFailed", comment: ""))
            return nil
        }
    }

    // Cancel all processing
    func stopProcessing() {
        // Set cancel flag safely using serial queue (barrier ensures exclusive write)
        activeTasksQueue.async(flags: .barrier) {
            self.shouldCancelProcessing = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Safely read a copy of activeTasks
            var tasksCopy: [ManagedTask] = []
            self.activeTasksQueue.sync {
                tasksCopy = self.activeTasks
            }

            for task in tasksCopy {
                if task.process.isRunning {
                    task.process.terminate()
                    task.process.waitUntilExit()
                }
            }

            DispatchQueue.main.async {
                self.logMessages.append(NSLocalizedString("ProcessingStopped", comment: ""))
                self.isProcessing = false

                // Safely clear activeTasks after stop
                self.activeTasksQueue.async(flags: .barrier) {
                    self.activeTasks.removeAll()
                }
            }
        }
    }

    // Processes a portion of an image (either whole or cropped)
    private func processImagePart(inputURL: URL, outputPath: String, cropParameters: (width: Int, height: Int, x: Int, y: Int)?, resizeHeight: Int, quality: Int, unsharpRadius: Float, unsharpSigma: Float, unsharpAmount: Float, unsharpThreshold: Float, useGrayColorspace: Bool, failedFiles: inout [String]) {
        // Safely read cancel flag
        var cancel = false
        activeTasksQueue.sync {
            cancel = self.shouldCancelProcessing
        }
        guard !cancel else {
            DispatchQueue.main.async {
                self.logMessages.append(String(
                    format: NSLocalizedString("CancelProcessingImagePart", comment: ""),
                    inputURL.lastPathComponent))
            }
            return
        }

        let outputFile = outputPath + ".jpg"
        var arguments = ["convert", inputURL.path]
        // Apply cropping if specified
        if let crop = cropParameters {
            arguments += ["-crop", "\(crop.width)x\(crop.height)+\(crop.x)+\(crop.y)"]
        }
        // Apply resizing and other transformations
        arguments += ["-resize", "x\(resizeHeight)"]

        if useGrayColorspace {
            arguments += ["-colorspace", "GRAY"]
        }

        // Only add -unsharp if unsharpAmount > 0
        if unsharpAmount > 0 {
            arguments += [
                "-unsharp", "\(unsharpRadius)x\(unsharpSigma)+\(unsharpAmount)+\(unsharpThreshold)"
            ]
        }
        arguments += [
            "-quality", "\(quality)",
            outputFile
        ]

        let magickTask = Process()
        magickTask.executableURL = URL(fileURLWithPath: gmPath)
        magickTask.arguments = arguments
        let errorPipe = Pipe()
        magickTask.standardError = errorPipe
        // Track active task
        activeTasksQueue.async {
            self.activeTasks.append(ManagedTask(process: magickTask))
        }

        do {
            try magickTask.run()
            magickTask.waitUntilExit()
            // Clean up completed task
            activeTasksQueue.async {
                self.activeTasks.removeAll { $0.process == magickTask }
            }

            if magickTask.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                failedFiles.append(inputURL.lastPathComponent)
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("ProcessImagePartFailed", comment: ""), inputURL.lastPathComponent, outputFile, errorMessage))
                }
            }
        } catch {
            failedFiles.append(inputURL.lastPathComponent)
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("ProcessImagePartFailed", comment: ""), inputURL.lastPathComponent, outputFile, error.localizedDescription))
            }
        }
    }

    // Main processing function
    func processImages(inputDir: URL, outputDir: URL, parameters: ProcessingParameters) {
        guard let threshold = Int(parameters.widthThreshold), threshold > 0 else {
            logMessages.append(NSLocalizedString("InvalidWidthThreshold", comment: ""))
            isProcessing = false
            return
        }
        guard let resize = Int(parameters.resizeHeight), resize > 0 else {
            logMessages.append(NSLocalizedString("InvalidResizeHeight", comment: ""))
            isProcessing = false
            return
        }
        guard let qual = Int(parameters.quality), qual >= 1, qual <= 100 else {
            logMessages.append(NSLocalizedString("InvalidOutputQuality", comment: ""))
            isProcessing = false
            return
        }
        guard let radius = Float(parameters.unsharpRadius), radius >= 0,
              let sigma = Float(parameters.unsharpSigma), sigma >= 0,
              let amount = Float(parameters.unsharpAmount), amount >= 0,
              let unsharpThreshold = Float(parameters.unsharpThreshold), unsharpThreshold >= 0
        else {
            logMessages.append(NSLocalizedString("InvalidUnsharpParameters", comment: ""))
            isProcessing = false
            return
        }

        isProcessing = true

        // Reset cancel flag using barrier write to ensure thread safety
        activeTasksQueue.async(flags: .barrier) {
            self.shouldCancelProcessing = false
        }

        // Reset counters
        totalImagesProcessed = 0
        processingStartTime = Date()

        // Clear activeTasks safely before starting
        activeTasksQueue.async(flags: .barrier) {
            self.activeTasks.removeAll()
        }

        // Log start with appropriate parameters
        if amount > 0 {
            logMessages.append(String(format: NSLocalizedString("StartProcessingWithUnsharp", comment: ""),
                                      threshold, resize, qual, parameters.threadCount, radius, sigma, amount, unsharpThreshold,
                                      NSLocalizedString(parameters.useGrayColorspace ? "GrayEnabled" : "GrayDisabled", comment: "")))
        } else {
            logMessages.append(String(format: NSLocalizedString("StartProcessingNoUnsharp", comment: ""),
                                      threshold, resize, qual, parameters.threadCount,
                                      NSLocalizedString(parameters.useGrayColorspace ? "GrayEnabled" : "GrayDisabled", comment: "")))
        }

        // Verify GM
        guard let detectedPath = detectGMPathViaWhich() else {
            logMessages.append(NSLocalizedString("CannotRunGraphicsMagick", comment: ""))
            isProcessing = false
            return
        }
        // Store valid GM path (avoids git merge's gm alias)
        gmPath = detectedPath

        let task = Process()
        task.executableURL = URL(fileURLWithPath: gmPath)
        task.arguments = ["--version"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let outputMessage = String(data: outputData, encoding: .utf8) ?? NSLocalizedString("CannotReadOutput", comment: "")
            if task.terminationStatus != 0 {
                logMessages.append(String(format: NSLocalizedString("GraphicsMagickRunFailed", comment: ""), outputMessage))
                isProcessing = false
                return
            } else {
                logMessages.append(String(format: NSLocalizedString("GraphicsMagickVersion", comment: ""), outputMessage))
            }
        } catch {
            logMessages.append(String(format: NSLocalizedString("CannotRunGraphicsMagick", comment: ""), error.localizedDescription))
            isProcessing = false
            return
        }
        // Create output directory
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logMessages.append(String(format: NSLocalizedString("CannotCreateOutputDir", comment: ""), error.localizedDescription))
            isProcessing = false
            return
        }

        // Process images asynchronously
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard !self.shouldCancelProcessing else {
                DispatchQueue.main.async {
                    self.logMessages.append(NSLocalizedString("ProcessingCancelledNoStart", comment: ""))
                    self.isProcessing = false
                }
                return
            }

            let fileManager = FileManager.default
            let imageExtensions = ["jpg", "jpeg", "png"]
            var failedFiles: [String] = []
            let failedFilesQueue = DispatchQueue(label: "me2.comic.me2comic.failedFiles", attributes: [])
            // Create concurrent queue for image processing tasks
            let processingQueue = DispatchQueue(label: "me2.comic.me2comic.processing", qos: .userInitiated, attributes: [.concurrent], target: .global(qos: .userInitiated))
            // Synchronize task completion with dispatch group
            let group = DispatchGroup()
            // Limit concurrent tasks based on thread count
            let semaphore = DispatchSemaphore(value: parameters.threadCount)

            do {
                let subdirectories = try fileManager.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: nil)
                for subdirectory in subdirectories {
                    guard !self.shouldCancelProcessing else {
                        DispatchQueue.main.async {
                            self.logMessages.append(NSLocalizedString("ProcessingCancelledSubdir", comment: ""))
                            self.isProcessing = false
                        }
                        break
                    }

                    guard subdirectory.hasDirectoryPath else { continue }
                    let subdirectoryName = subdirectory.lastPathComponent
                    let subOutputDir = outputDir.appendingPathComponent(subdirectoryName)

                    do {
                        try fileManager.createDirectory(at: subOutputDir, withIntermediateDirectories: true, attributes: nil)
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("StartProcessingSubdir", comment: ""), subdirectoryName))
                        }

                        var isSubdirectoryCompleted = true
                        let files = try fileManager.contentsOfDirectory(at: subdirectory, includingPropertiesForKeys: nil)
                        for file in files {
                            guard !self.shouldCancelProcessing else {
                                DispatchQueue.main.async {
                                    self.logMessages.append(String(format: NSLocalizedString("ProcessingCancelledFiles", comment: ""), ""))
                                    self.isProcessing = false
                                }
                                isSubdirectoryCompleted = false
                                break
                            }

                            guard imageExtensions.contains(file.pathExtension.lowercased()) else { continue }

                            group.enter()
                            semaphore.wait() // Acquire semaphore
                            processingQueue.async {
                                defer {
                                    semaphore.signal() // Release semaphore
                                    group.leave()
                                }

                                guard !self.shouldCancelProcessing else { return }
                                var localFailedFiles: [String] = []
                                self.processImage(file, outputDir: subOutputDir, failedFiles: &localFailedFiles, widthThreshold: threshold, resizeHeight: resize, quality: qual, unsharpRadius: radius, unsharpSigma: sigma, unsharpAmount: amount, unsharpThreshold: unsharpThreshold, useGrayColorspace: parameters.useGrayColorspace)
                                failedFilesQueue.sync {
                                    failedFiles.append(contentsOf: localFailedFiles)
                                }
                                DispatchQueue.main.async {
                                    self.totalImagesProcessed += 1
                                }
                            }
                        }
                        if isSubdirectoryCompleted && !self.shouldCancelProcessing {
                            DispatchQueue.main.async {
                                self.logMessages.append(String(format: NSLocalizedString("CompleteProcessingSubdir", comment: ""), subdirectoryName))
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("SubdirProcessingFailed", comment: ""), subdirectoryName, error.localizedDescription))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("CannotReadInputDir", comment: ""), error.localizedDescription))
                }
            }
            // Final completion handler
            group.notify(queue: .main) { [failedFiles] in
                if !self.shouldCancelProcessing {
                    // Log failed files
                    if !failedFiles.isEmpty {
                        self.logMessages.append(NSLocalizedString("FailedFilesList", comment: ""))
                        failedFiles.forEach { self.logMessages.append("- \($0)") }
                    }

                    // Unified log output in correct order
                    DispatchQueue.main.async {
                        // Log total number of processed images
                        self.logMessages.append(String(format: NSLocalizedString("TotalImagesProcessed", comment: ""), self.totalImagesProcessed))

                        // Log processing time
                        if let startTime = self.processingStartTime {
                            let elapsedTime = Date().timeIntervalSince(startTime)
                            if elapsedTime < 60 {
                                self.logMessages.append(String(format: NSLocalizedString("ProcessingTimeSeconds", comment: ""), Int(elapsedTime)))
                            } else {
                                self.logMessages.append(String(format: NSLocalizedString("ProcessingTimeMinutes", comment: ""), Int(elapsedTime / 60)))
                            }
                        }

                        // Log that processing is completed
                        self.logMessages.append(NSLocalizedString("ProcessingCompleted", comment: ""))

                        // Create notification for task completion
                        let content = UNMutableNotificationContent()
                        content.title = NSLocalizedString("TaskCompletedTitle", comment: "")
                        content.body = NSLocalizedString("TaskCompletedBody", comment: "")
                        content.sound = UNNotificationSound.default

                        // Send notification request
                        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(request)
                    }
                }
                self.isProcessing = false
            }
        }
    }

    // Process single image with cropping and resizing
    private func processImage(_ imageURL: URL, outputDir: URL, failedFiles: inout [String], widthThreshold: Int, resizeHeight: Int, quality: Int, unsharpRadius: Float, unsharpSigma: Float, unsharpAmount: Float, unsharpThreshold: Float, useGrayColorspace: Bool) {
        guard !shouldCancelProcessing else {
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("CancelProcessingImage", comment: ""), imageURL.lastPathComponent))
            }
            return
        }

        let filename = imageURL.lastPathComponent
        let filenameNoExt = imageURL.deletingPathExtension().lastPathComponent
        let outputPath = outputDir.appendingPathComponent(filenameNoExt).path
        // Get image dimensions
        let task = Process()
        task.executableURL = URL(fileURLWithPath: gmPath)
        task.arguments = ["identify", "-format", "%w %h", imageURL.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard task.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("CannotGetImageDimensions", comment: ""), filename))
                }
                failedFiles.append(filename)
                return
            }

            let dimensions = output.split(separator: " ").compactMap { Int($0) }
            guard dimensions.count == 2 else {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("CannotGetImageDimensions", comment: ""), filename))
                }
                failedFiles.append(filename)
                return
            }

            let width = dimensions[0]
            let height = dimensions[1]
            // Process whole image if below threshold width
            if width < widthThreshold {
                processImagePart(inputURL: imageURL, outputPath: outputPath, cropParameters: nil, resizeHeight: resizeHeight, quality: quality, unsharpRadius: unsharpRadius, unsharpSigma: unsharpSigma, unsharpAmount: unsharpAmount, unsharpThreshold: unsharpThreshold, useGrayColorspace: useGrayColorspace, failedFiles: &failedFiles)
            } else {
                // Split wide image into two parts
                let cropWidth = width / 2

                // Process right half (-1.jpg)
                let rightCrop = (width: cropWidth, height: height, x: cropWidth, y: 0)
                processImagePart(inputURL: imageURL, outputPath: "\(outputPath)-1", cropParameters: rightCrop, resizeHeight: resizeHeight, quality: quality, unsharpRadius: unsharpRadius, unsharpSigma: unsharpSigma, unsharpAmount: unsharpAmount, unsharpThreshold: unsharpThreshold, useGrayColorspace: useGrayColorspace, failedFiles: &failedFiles)

                guard !shouldCancelProcessing else {
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("CancelProcessImagePart2", comment: ""), filename))
                    }
                    return
                }
                // Process left half (-2.jpg)
                let leftCrop = (width: cropWidth, height: height, x: 0, y: 0)
                processImagePart(inputURL: imageURL, outputPath: "\(outputPath)-2", cropParameters: leftCrop, resizeHeight: resizeHeight, quality: quality, unsharpRadius: unsharpRadius, unsharpSigma: unsharpSigma, unsharpAmount: unsharpAmount, unsharpThreshold: unsharpThreshold, useGrayColorspace: useGrayColorspace, failedFiles: &failedFiles)
            }
        } catch {
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("ProcessImageFailed", comment: ""), filename, error.localizedDescription))
            }
            failedFiles.append(filename)
        }
    }
}
