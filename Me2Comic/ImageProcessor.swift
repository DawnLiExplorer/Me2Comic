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
    private var shouldCancelProcessing: Bool = false
    private var totalImagesProcessed: Int = 0
    private var processingStartTime: Date?

    // Log messages and processing status
    @Published var isProcessing: Bool = false
    @Published var logMessages: [String] = [] {
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
                self.logMessages.append(NSLocalizedString("ProcessingStopped", comment: ""))
                self.isProcessing = false
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

        isProcessing = true // Enable processing flag
        shouldCancelProcessing = false // clear cancel flag
        totalImagesProcessed = 0 // reset counter
        processingStartTime = Date() // record start time
        activeTasksQueue.async { // 清空 activeTasks
            self.activeTasks.removeAll()
        }
        // Unsharp on off
        if amount > 0 {
            logMessages.append(String(format: NSLocalizedString("StartProcessingWithUnsharp", comment: ""),
                                      threshold, resize, qual, parameters.threadCount, radius, sigma, amount, unsharpThreshold,
                                      NSLocalizedString(parameters.useGrayColorspace ? "GrayEnabled" : "GrayDisabled", comment: "")))
        } else {
            logMessages.append(String(format: NSLocalizedString("StartProcessingNoUnsharp", comment: ""),
                                      threshold, resize, qual, parameters.threadCount))
        }

        // Verify GM
        guard let detectedPath = detectGMPathViaWhich() else {
            logMessages.append(NSLocalizedString("CannotRunGraphicsMagick", comment: ""))
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

            group.notify(queue: .main) { [failedFiles] in
                if !self.shouldCancelProcessing {
                    // Log failed files
                    if !failedFiles.isEmpty {
                        self.logMessages.append(NSLocalizedString("FailedFilesList", comment: ""))
                        failedFiles.forEach { self.logMessages.append("- \($0)\n") }
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

                activeTasksQueue.async { // 添加任务
                    self.activeTasks.append(ManagedTask(process: magickTask))
                }

                do {
                    try magickTask.run()
                    magickTask.waitUntilExit()

                    activeTasksQueue.async { // 移除任务
                        self.activeTasks.removeAll { $0.process == magickTask }
                    }

                    if magickTask.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                        failedFiles.append(filename)
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessSingleImageFailed", comment: ""), filename, errorMessage))
                        }
                    }
                } catch {
                    failedFiles.append(filename)
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("ProcessSingleImageFailed", comment: ""), filename, error.localizedDescription))
                    }
                }
            } else {
                let cropWidth = width / 2
                let outputFile1 = "\(outputPath)-1.jpg"
                var arguments1 = [
                    "convert",
                    imageURL.path,
                    "-crop", "\(cropWidth)x\(height)+\(cropWidth)+0",
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

                activeTasksQueue.async { // 添加任务
                    self.activeTasks.append(ManagedTask(process: magickTask1))
                }

                do {
                    try magickTask1.run()
                    magickTask1.waitUntilExit()

                    activeTasksQueue.async { // 移除任务
                        self.activeTasks.removeAll { $0.process == magickTask1 }
                    }

                    if magickTask1.terminationStatus != 0 {
                        let errorData = errorPipe1.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart1Failed", comment: ""), filename, filenameNoExt, errorMessage))
                        }
                        failedFiles.append(filename)
                    }
                } catch {
                    failedFiles.append(filename)
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart1Failed", comment: ""), filename, filenameNoExt, error.localizedDescription))
                    }
                }

                guard !shouldCancelProcessing else {
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("CancelProcessImagePart2", comment: ""), filename))
                    }
                    return
                }

                let outputFile2 = "\(outputPath)-2.jpg"
                var arguments2 = [
                    "convert",
                    imageURL.path,
                    "-crop", "\(cropWidth)x\(height)+0+0",
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

                activeTasksQueue.async { // 添加任务
                    self.activeTasks.append(ManagedTask(process: magickTask2))
                }

                do {
                    try magickTask2.run()
                    magickTask2.waitUntilExit()

                    activeTasksQueue.async { // 移除任务
                        self.activeTasks.removeAll { $0.process == magickTask2 }
                    }

                    if magickTask2.terminationStatus != 0 {
                        let errorData = errorPipe2.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                        DispatchQueue.main.async {
                            self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart2Failed", comment: ""), filename, filenameNoExt, errorMessage))
                        }
                        failedFiles.append(filename)
                    }
                } catch {
                    failedFiles.append(filename)
                    DispatchQueue.main.async {
                        self.logMessages.append(String(format: NSLocalizedString("ProcessImagePart2Failed", comment: ""), filename, filenameNoExt, error.localizedDescription))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("ProcessImageFailed", comment: ""), filename, error.localizedDescription))
            }
            failedFiles.append(filename)
        }
    }
}
