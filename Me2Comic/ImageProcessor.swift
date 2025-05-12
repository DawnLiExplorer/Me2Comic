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
    private var shouldCancelProcessing: Bool = false
    private var totalImagesProcessed: Int = 0
    private var processingStartTime: Date?

    // Log messages and processing status
    @Published var logMessages: [String] = []
    @Published var isProcessing: Bool = false

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
                logMessages.append(String(format: NSLocalizedString("WhichGMException", comment: ""), errorMessage) + "\n")
                return nil
            }
            return output
        } catch {
            logMessages.append(NSLocalizedString("WhichGMFailed", comment: "") + "\n")
            return nil
        }
    }

    // Cancel all processing
    func stopProcessing() {
        shouldCancelProcessing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let tasks = self.activeTasks
            for task in tasks {
                if task.process.isRunning {
                    task.process.terminate()
                    task.process.waitUntilExit()
                }
            }
            DispatchQueue.main.async {
                self.activeTasks.removeAll()
                self.logMessages.append(NSLocalizedString("ProcessingStopped", comment: "") + "\n")
                self.isProcessing = false
            }
        }
    }

    // Main processing function
    func processImages(inputDir: URL, outputDir: URL, parameters: ProcessingParameters) {
        guard let threshold = Int(parameters.widthThreshold), threshold > 0 else {
            logMessages.append(NSLocalizedString("InvalidWidthThreshold", comment: "") + "\n")
            isProcessing = false
            return
        }
        guard let resize = Int(parameters.resizeHeight), resize > 0 else {
            logMessages.append(NSLocalizedString("InvalidResizeHeight", comment: "") + "\n")
            isProcessing = false
            return
        }
        guard let qual = Int(parameters.quality), qual >= 1, qual <= 100 else {
            logMessages.append(NSLocalizedString("InvalidOutputQuality", comment: "") + "\n")
            isProcessing = false
            return
        }
        guard let radius = Float(parameters.unsharpRadius), radius >= 0,
              let sigma = Float(parameters.unsharpSigma), sigma >= 0,
              let amount = Float(parameters.unsharpAmount), amount >= 0,
              let unsharpThreshold = Float(parameters.unsharpThreshold), unsharpThreshold >= 0
        else {
            logMessages.append(NSLocalizedString("InvalidUnsharpParameters", comment: "") + "\n")
            isProcessing = false
            return
        }

        isProcessing = true // Enable processing flag
        shouldCancelProcessing = false // clear cancel flag
        totalImagesProcessed = 0 // reset counter
        activeTasks.removeAll() // clear task queue
        processingStartTime = Date() // record start time
        // Unsharp on off
        if amount > 0 {
            logMessages.append(String(format: NSLocalizedString("StartProcessingWithUnsharp", comment: ""),
                                      threshold, resize, qual, parameters.threadCount, radius, sigma, amount, unsharpThreshold,
                                      NSLocalizedString(parameters.useGrayColorspace ? "GrayEnabled" : "GrayDisabled", comment: "")) + "\n")
        } else {
            logMessages.append(String(format: NSLocalizedString("StartProcessingNoUnsharp", comment: ""),
                                      threshold, resize, qual, parameters.threadCount) + "\n")
        }

        // Verify GM
        guard let detectedPath = detectGMPathViaWhich() else {
            logMessages.append(NSLocalizedString("CannotRunGraphicsMagick", comment: "") + "\n")
            isProcessing = false
            return
        }
        gmPath = detectedPath // Store valid GM path

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
                logMessages.append(String(format: NSLocalizedString("GraphicsMagickRunFailed", comment: ""), outputMessage) + "\n")
                isProcessing = false
                return
            } else {
                logMessages.append(String(format: NSLocalizedString("GraphicsMagickVersion", comment: ""), outputMessage) + "\n")
            }
        } catch {
            logMessages.append(String(format: NSLocalizedString("CannotRunGraphicsMagick", comment: ""), error.localizedDescription) + "\n")
            isProcessing = false
            return
        }

        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logMessages.append(String(format: NSLocalizedString("CannotCreateOutputDir", comment: ""), error.localizedDescription) + "\n")
            isProcessing = false
            return
        }

        // Process images asynchronously
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard !self.shouldCancelProcessing else {
                DispatchQueue.main.async {
                    self.logMessages.append(NSLocalizedString("ProcessingCancelledNoStart", comment: "") + "\n")
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
                            self.logMessages.append(NSLocalizedString("ProcessingCancelledSubdir", comment: "") + "\n")
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
                            self.logMessages.append(String(format: NSLocalizedString("StartProcessingSubdir", comment: ""), subdirectoryName) + "\n")
                        }

                        var isSubdirectoryCompleted = true
                        let files = try fileManager.contentsOfDirectory(at: subdirectory, includingPropertiesForKeys: nil)
                        for file in files {
                            guard !self.shouldCancelProcessing else {
                                DispatchQueue.main.async {
                                    self.logMessages.append(String(format: NSLocalizedString("ProcessingCancelledFiles", comment: ""), "") + "\n")
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
                                self.logMessages.append(String(format: NSLocalizedString("CompleteProcessingSubdir", comment: ""), subdirectoryName) + "\n")
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("SubdirProcessingFailed", comment: ""), subdirectoryName, error.localizedDescription) + "\n")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("CannotReadInputDir", comment: ""), error.localizedDescription) + "\n")
                }
            }

            group.notify(queue: .main) { [failedFiles] in
                if !self.shouldCancelProcessing {
                    // Log failed files
                    if !failedFiles.isEmpty {
                        self.logMessages.append(NSLocalizedString("FailedFilesList", comment: "") + "\n")
                        failedFiles.forEach { self.logMessages.append("- \($0)\n") }
                    }
                    // Log processing stats
                    self.logMessages.append(String(format: NSLocalizedString("TotalImagesProcessed", comment: ""), self.totalImagesProcessed) + "\n")
                    // Timer
                    if let startTime = self.processingStartTime {
                        let elapsedTime = Date().timeIntervalSince(startTime)
                        if elapsedTime < 60 {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessingTimeSeconds", comment: ""), Int(elapsedTime)) + "\n")
                        } else {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessingTimeMinutes", comment: ""), Int(elapsedTime / 60)) + "\n")
                        }
                    }
                    self.logMessages.append(NSLocalizedString("ProcessingCompleted", comment: "") + "\n")
                    // Create notification for task completion
                    let content = UNMutableNotificationContent()
                    content.title = NSLocalizedString("TaskCompletedTitle", comment: "")
                    content.body = NSLocalizedString("TaskCompletedBody", comment: "")
                    content.sound = UNNotificationSound.default
                    // Send notification request
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                self.isProcessing = false
            }
        }
    }

    // Process single image with cropping and resizing
    private func processImage(_ imageURL: URL, outputDir: URL, failedFiles: inout [String], widthThreshold: Int, resizeHeight: Int, quality: Int, unsharpRadius: Float, unsharpSigma: Float, unsharpAmount: Float, unsharpThreshold: Float, useGrayColorspace: Bool) {
        guard !shouldCancelProcessing else {
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("CancelProcessingImage", comment: ""), imageURL.lastPathComponent) + "\n")
            }
            return
        }

        let filename = imageURL.lastPathComponent
        let filenameNoExt = imageURL.deletingPathExtension().lastPathComponent
        let outputPath = outputDir.appendingPathComponent(filenameNoExt).path

        let task = Process()
        task.executableURL = URL(fileURLWithPath: gmPath)
        task.arguments = ["identify", "-format", "%w %h", imageURL.path] // Get image dimensions
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
                    self.logMessages.append(String(format: NSLocalizedString("CannotGetImageDimensions", comment: ""), filename) + "\n")
                }
                failedFiles.append(filename)
                return
            }

            let dimensions = output.split(separator: " ").compactMap { Int($0) }
            guard dimensions.count == 2 else {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("CannotGetImageDimensions", comment: ""), filename) + "\n")
                }
                failedFiles.append(filename)
                return
            }

            let width = dimensions[0]
            let height = dimensions[1]
            // if below width threshold
            if width < widthThreshold {
                let outputFile = "\(outputPath).jpg"
                var arguments = [
                    "convert",
                    imageURL.path,
                    "-resize", "x\(resizeHeight)"
                ]
                if useGrayColorspace {
                    arguments += ["-colorspace", "GRAY"]
                }
                arguments += [
                    "-unsharp", "\(unsharpRadius)x\(unsharpSigma)+\(unsharpAmount)+\(unsharpThreshold)",
                    "-quality", "\(quality)",
                    outputFile
                ]

                let magickTask = Process()
                magickTask.executableURL = URL(fileURLWithPath: gmPath)
                magickTask.arguments = arguments
                let errorPipe = Pipe()
                magickTask.standardError = errorPipe

                activeTasks.append(ManagedTask(process: magickTask))

                do {
                    try magickTask.run()
                    magickTask.waitUntilExit()

                    if magickTask.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                        failedFiles.append(filename)
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessSingleImageFailed", comment: ""), filename, errorMessage) + "\n")
                        }
                    }
                } catch {
                    failedFiles.append(filename)
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("ProcessSingleImageFailed", comment: ""), filename, error.localizedDescription) + "\n")
                    }
                }
            } else {
                let cropWidth = width / 2
                let outputFile1 = "\(outputPath)-1.jpg"
                var arguments1 = [
                    "convert",
                    imageURL.path,
                    "-crop", "\(cropWidth)x\(height)+\(cropWidth)+0", // Crop right half starting at cropWidth
                    "-resize", "x\(resizeHeight)"
                ]
                if useGrayColorspace {
                    arguments1 += ["-colorspace", "GRAY"]
                }
                arguments1 += [
                    "-unsharp", "\(unsharpRadius)x\(unsharpSigma)+\(unsharpAmount)+\(unsharpThreshold)",
                    "-quality", "\(quality)",
                    outputFile1
                ]

                let magickTask1 = Process()
                magickTask1.executableURL = URL(fileURLWithPath: gmPath)
                magickTask1.arguments = arguments1
                let errorPipe1 = Pipe()
                magickTask1.standardError = errorPipe1

                activeTasks.append(ManagedTask(process: magickTask1))

                do {
                    try magickTask1.run()
                    magickTask1.waitUntilExit()

                    if magickTask1.terminationStatus != 0 {
                        let errorData = errorPipe1.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart1Failed", comment: ""), filename, filenameNoExt, errorMessage) + "\n")
                        }
                        failedFiles.append(filename)
                    }
                } catch {
                    failedFiles.append(filename)
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart1Failed", comment: ""), filename, filenameNoExt, error.localizedDescription) + "\n")
                    }
                }

                guard !shouldCancelProcessing else {
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("CancelProcessImagePart2", comment: ""), filename) + "\n")
                    }
                    return
                }
                // Process left half
                let outputFile2 = "\(outputPath)-2.jpg"
                var arguments2 = [
                    "convert",
                    imageURL.path,
                    "-crop", "\(cropWidth)x\(height)+0+0", // Crop left half
                    "-resize", "x\(resizeHeight)"
                ]
                if useGrayColorspace {
                    arguments2 += ["-colorspace", "GRAY"]
                }
                arguments2 += [
                    "-unsharp", "\(unsharpRadius)x\(unsharpSigma)+\(unsharpAmount)+\(unsharpThreshold)",
                    "-quality", "\(quality)",
                    outputFile2
                ]

                let magickTask2 = Process()
                magickTask2.executableURL = URL(fileURLWithPath: gmPath)
                magickTask2.arguments = arguments2
                let errorPipe2 = Pipe()
                magickTask2.standardError = errorPipe2

                activeTasks.append(ManagedTask(process: magickTask2))

                do {
                    try magickTask2.run()
                    magickTask2.waitUntilExit()

                    if magickTask2.terminationStatus != 0 {
                        let errorData = errorPipe2.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart2Failed", comment: ""), filename, filenameNoExt, errorMessage) + "\n")
                        }
                        failedFiles.append(filename)
                    }
                } catch {
                    failedFiles.append(filename)
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart2Failed", comment: ""), filename, filenameNoExt, error.localizedDescription) + "\n")
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("ProcessImageFailed", comment: ""), filename, error.localizedDescription) + "\n")
            }
            failedFiles.append(filename)
        }
    }
}
