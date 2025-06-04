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

    // Safely detect GraphicsMagick executable path with predefined paths
    private func detectGMPathSafely() -> String? {
        // First check known safe paths
        let knownPaths = ["/opt/homebrew/bin/gm", "/usr/local/bin/gm", "/usr/bin/gm"]

        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to which command if known paths don't exist
        return detectGMPathViaWhich()
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

    // Properly escape path for shell command
    private func escapePathForShell(_ path: String) -> String {
        // Replace backslashes with double backslashes
        var escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")

        // Replace double quotes with escaped double quotes
        escapedPath = escapedPath.replacingOccurrences(of: "\"", with: "\\\"")

        // Wrap in double quotes to handle spaces and special characters
        return "\"\(escapedPath)\""
    }

    // Generate batch command
    private func buildConvertCommand(
        inputPath: String,
        outputPath: String,
        cropParams: String?,
        resizeHeight: Int,
        quality: Int,
        unsharpRadius: Float,
        unsharpSigma: Float,
        unsharpAmount: Float,
        unsharpThreshold: Float,
        useGrayColorspace: Bool
    ) -> String {
        // Escape paths for shell command
        let escapedInputPath = escapePathForShell(inputPath)
        let escapedOutputPath = escapePathForShell(outputPath)

        var command = "convert \(escapedInputPath)"

        // Add crop parameters
        if let crop = cropParams {
            command += " -crop \(crop)"
        }

        // Add resize parameters
        command += " -resize x\(resizeHeight)"

        // Add colorspace parameters
        if useGrayColorspace {
            command += " -colorspace GRAY"
        }

        // Add unsharp parameters
        if unsharpAmount > 0 {
            command += " -unsharp \(unsharpRadius)x\(unsharpSigma)+\(unsharpAmount)+\(unsharpThreshold)"
        }

        // Add quality parameters and output path
        command += " -quality \(quality) \(escapedOutputPath)"

        return command
    }

    // Process images in batch for a subdirectory
    private func processBatchImages(
        subdirectory: URL,
        outputDir: URL,
        widthThreshold: Int,
        resizeHeight: Int,
        quality: Int,
        unsharpRadius: Float,
        unsharpSigma: Float,
        unsharpAmount: Float,
        unsharpThreshold: Float,
        useGrayColorspace: Bool,
        failedFiles: inout [String]
    ) -> Int {
        // Check cancellation flag
        var cancel = false
        activeTasksQueue.sync {
            cancel = self.shouldCancelProcessing
        }
        if cancel { return 0 }

        let fileManager = FileManager.default
        let imageExtensions = ["jpg", "jpeg", "png"]
        var processedCount = 0

        do {
            // Get all files in subdirectory
            let files = try fileManager.contentsOfDirectory(at: subdirectory, includingPropertiesForKeys: nil)
            let imageFiles = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }

            // If no image files, return immediately
            if imageFiles.isEmpty {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("NoImagesInDir", comment: ""), subdirectory.lastPathComponent))
                }
                return 0
            }

            // Create temporary batch file
            let batchFilePath = FileManager.default.temporaryDirectory.appendingPathComponent("me2comic_batch_\(UUID().uuidString).txt")
            var batchCommands = ""

            // Process each image file
            for imageFile in imageFiles {
                // Check cancellation flag again
                activeTasksQueue.sync {
                    cancel = self.shouldCancelProcessing
                }
                if cancel { break }

                let filename = imageFile.lastPathComponent
                let filenameWithoutExt = filename.split(separator: ".").dropLast().joined(separator: ".")
                let outputBasePath = outputDir.appendingPathComponent(filenameWithoutExt).path

                // Get image dimensions
                do {
                    let dimensionsTask = Process()
                    dimensionsTask.executableURL = URL(fileURLWithPath: gmPath)
                    dimensionsTask.arguments = ["identify", "-format", "%w %h", imageFile.path]

                    let pipe = Pipe()
                    dimensionsTask.standardOutput = pipe
                    dimensionsTask.standardError = pipe

                    try dimensionsTask.run()
                    dimensionsTask.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard dimensionsTask.terminationStatus == 0,
                          let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !output.isEmpty
                    else {
                        failedFiles.append(filename)
                        continue
                    }

                    let dimensions = output.split(separator: " ")
                    guard dimensions.count == 2,
                          let width = Int(dimensions[0]),
                          let height = Int(dimensions[1])
                    else {
                        failedFiles.append(filename)
                        continue
                    }

                    // Process based on width threshold
                    if width < widthThreshold {
                        // Process entire image
                        let command = buildConvertCommand(
                            inputPath: imageFile.path,
                            outputPath: "\(outputBasePath).jpg",
                            cropParams: nil,
                            resizeHeight: resizeHeight,
                            quality: quality,
                            unsharpRadius: unsharpRadius,
                            unsharpSigma: unsharpSigma,
                            unsharpAmount: unsharpAmount,
                            unsharpThreshold: unsharpThreshold,
                            useGrayColorspace: useGrayColorspace
                        )
                        batchCommands.append(command + "\n")
                        processedCount += 1
                    } else {
                        // Split into left and right parts
                        let cropWidth = width / 2

                        // Process right half (-1.jpg)
                        let rightCropCommand = buildConvertCommand(
                            inputPath: imageFile.path,
                            outputPath: "\(outputBasePath)-1.jpg",
                            cropParams: "\(cropWidth)x\(height)+\(cropWidth)+0",
                            resizeHeight: resizeHeight,
                            quality: quality,
                            unsharpRadius: unsharpRadius,
                            unsharpSigma: unsharpSigma,
                            unsharpAmount: unsharpAmount,
                            unsharpThreshold: unsharpThreshold,
                            useGrayColorspace: useGrayColorspace
                        )
                        batchCommands.append(rightCropCommand + "\n")

                        // Process left half (-2.jpg)
                        let leftCropCommand = buildConvertCommand(
                            inputPath: imageFile.path,
                            outputPath: "\(outputBasePath)-2.jpg",
                            cropParams: "\(cropWidth)x\(height)+0+0",
                            resizeHeight: resizeHeight,
                            quality: quality,
                            unsharpRadius: unsharpRadius,
                            unsharpSigma: unsharpSigma,
                            unsharpAmount: unsharpAmount,
                            unsharpThreshold: unsharpThreshold,
                            useGrayColorspace: useGrayColorspace
                        )
                        batchCommands.append(leftCropCommand + "\n")
                        processedCount += 1
                    }
                } catch {
                    failedFiles.append(filename)
                }
            }

            // If no commands or cancelled, clean up and return
            if batchCommands.isEmpty || cancel {
                try? fileManager.removeItem(at: batchFilePath)
                return processedCount
            }

            // Write batch file
            do {
                try batchCommands.write(to: batchFilePath, atomically: true, encoding: .utf8)

                // Execute batch command
                let batchTask = Process()
                batchTask.executableURL = URL(fileURLWithPath: gmPath)
                batchTask.arguments = ["batch", "-stop-on-error", "off"]

                let inputPipe = Pipe()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                batchTask.standardInput = inputPipe
                batchTask.standardOutput = outputPipe
                batchTask.standardError = errorPipe

                // Track active task
                let managedTask = ManagedTask(process: batchTask)
                activeTasksQueue.async {
                    self.activeTasks.append(managedTask)
                }

                // Read batch file content
                let batchContent = try String(contentsOf: batchFilePath)
                let data = batchContent.data(using: .utf8)!

                try batchTask.run()

                // Write batch commands to stdin
                inputPipe.fileHandleForWriting.write(data)
                inputPipe.fileHandleForWriting.closeFile()

                batchTask.waitUntilExit()

                // Clean up completed task
                activeTasksQueue.async {
                    self.activeTasks.removeAll { $0.id == managedTask.id }
                }

                // Delete temporary batch file
                try? fileManager.removeItem(at: batchFilePath)

                // Handle errors if any
                if batchTask.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    if let errorMessage = String(data: errorData, encoding: .utf8), !errorMessage.isEmpty {
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("BatchProcessFailed", comment: ""), errorMessage))
                        }
                    }

                    // Add failed files to list
                    failedFiles.append(contentsOf: imageFiles.map { $0.lastPathComponent })
                    return 0
                }

                return processedCount
            } catch {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("BatchProcessFailed", comment: ""), error.localizedDescription))
                }
                try? fileManager.removeItem(at: batchFilePath)
                return 0
            }
        } catch {
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("CannotReadInputDir", comment: ""), error.localizedDescription))
            }
            return 0
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

        // Detect GraphicsMagick path
        if gmPath.isEmpty {
            guard let detectedPath = detectGMPathSafely() else {
                logMessages.append(NSLocalizedString("GMNotFound", comment: ""))
                isProcessing = false
                return
            }
            gmPath = detectedPath
            logMessages.append(String(format: NSLocalizedString("UsingGM", comment: ""), gmPath))
        }

        // Get GraphicsMagick version
        let versionTask = Process()
        versionTask.executableURL = URL(fileURLWithPath: gmPath)
        versionTask.arguments = ["--version"]
        let versionPipe = Pipe()
        versionTask.standardOutput = versionPipe
        versionTask.standardError = versionPipe

        do {
            try versionTask.run()
            versionTask.waitUntilExit()
            let outputData = versionPipe.fileHandleForReading.readDataToEndOfFile()
            let outputMessage = String(data: outputData, encoding: .utf8) ?? NSLocalizedString("CannotReadOutput", comment: "")
            if versionTask.terminationStatus == 0 {
                logMessages.append(String(format: NSLocalizedString("GraphicsMagickVersion", comment: ""), outputMessage))
            }
        } catch {
            // Ignore version errors, continue with main processing
        }

        // Create output directory if it doesn't exist
        let fileManager = FileManager.default
        do {
            if !fileManager.fileExists(atPath: outputDir.path) {
                try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
            }
        } catch {
            logMessages.append(String(format: NSLocalizedString("CannotCreateOutputDir", comment: ""), error.localizedDescription))
            isProcessing = false
            return
        }

        // Process in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var failedFiles: [String] = []
            var totalProcessed = 0

            do {
                // Get subdirectories
                let subdirectories = try fileManager.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: [.isDirectoryKey])
                    .filter { url in
                        guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                              let isDirectory = resourceValues.isDirectory
                        else { return false }
                        return isDirectory
                    }

                // Process each subdirectory
                for subdirectory in subdirectories {
                    // Check cancellation flag
                    var cancel = false
                    self.activeTasksQueue.sync {
                        cancel = self.shouldCancelProcessing
                    }
                    if cancel { break }

                    let subdirName = subdirectory.lastPathComponent

                    // Create corresponding output subdirectory
                    let outputSubdir = outputDir.appendingPathComponent(subdirName)
                    do {
                        if !fileManager.fileExists(atPath: outputSubdir.path) {
                            try fileManager.createDirectory(at: outputSubdir, withIntermediateDirectories: true)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("CannotCreateOutputSubdir", comment: ""), subdirName, error.localizedDescription))
                        }
                        continue
                    }

                    // Log processing start for subdirectory
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("StartProcessingSubdir", comment: ""), subdirName))
                    }

                    // Process images in subdirectory
                    let processed = self.processBatchImages(
                        subdirectory: subdirectory,
                        outputDir: outputSubdir,
                        widthThreshold: threshold,
                        resizeHeight: resize,
                        quality: qual,
                        unsharpRadius: radius,
                        unsharpSigma: sigma,
                        unsharpAmount: amount,
                        unsharpThreshold: unsharpThreshold,
                        useGrayColorspace: parameters.useGrayColorspace,
                        failedFiles: &failedFiles
                    )

                    // Update total count
                    totalProcessed += processed

                    // Log processing completion for subdirectory
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("ProcessedSubdir", comment: ""), subdirName))
                    }

                    // Check cancellation flag again
                    self.activeTasksQueue.sync {
                        cancel = self.shouldCancelProcessing
                    }
                    if cancel { break }
                }

                // Calculate processing time
                let processingTime = Date().timeIntervalSince(self.processingStartTime ?? Date())

                // Log final statistics
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("TotalImagesProcessed", comment: ""), totalProcessed))

                    if !failedFiles.isEmpty {
                        self.logMessages.append(String(format: NSLocalizedString("FailedFiles", comment: ""), failedFiles.count))
                    }

                    self.logMessages.append(NSLocalizedString("ProcessingCompleted", comment: ""))
                    self.logMessages.append(String(format: NSLocalizedString("TotalProcessingTime", comment: ""), Int(processingTime)))

                    // Send notification
                    self.sendCompletionNotification(totalProcessed: totalProcessed, failedCount: failedFiles.count)

                    // Reset processing state
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("ProcessingFailed", comment: ""), error.localizedDescription))
                    self.isProcessing = false
                }
            }
        }
    }

    // Send notification when processing is complete
    private func sendCompletionNotification(totalProcessed: Int, failedCount: Int) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("ProcessingCompletedTitle", comment: "")

        if failedCount > 0 {
            content.body = String(format: NSLocalizedString("ProcessingCompletedWithFailures", comment: ""), totalProcessed, failedCount)
        } else {
            content.body = String(format: NSLocalizedString("ProcessingCompletedSuccess", comment: ""), totalProcessed)
        }

        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
