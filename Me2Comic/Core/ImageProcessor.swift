//
//  ImageProcessor.swift
//  Me2Comic
//
//  Created by Me2 on 2025/5/12.
//

import Combine
import Foundation
import UserNotifications

class ImageProcessor: ObservableObject {
    private var gmPath: String = ""
    private var activeTasks: [ManagedTask] = []
    private let activeTasksQueue = DispatchQueue(label: "me2.comic.me2comic.activeTasks")
    private var shouldCancelProcessing: Bool = false // Cancellation flag
    private var totalImagesProcessed: Int = 0 // Progress counter
    private var processingStartTime: Date?
    private let processedCountQueue = DispatchQueue(label: "me2.comic.me2comic.processedCount")

    // Log messages and processing status
    @Published var isProcessing: Bool = false
    @Published var logMessages: [String] = [] { // limited to 100 entries
        didSet {
            if logMessages.count > 100 {
                logMessages.removeFirst(logMessages.count - 100)
            }
        }
    }

    // Cancel all processing tasks
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

    // Process a batch of images
    private func processBatchImages(
        images: [URL],
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
        var processedCount = 0
            
        // Early return if no images
        if images.isEmpty { return 0 }
            
        // STEP 1: Batch get dimensions for all valid images
        let supportedExtensions = ["jpg", "jpeg", "png"]
        let validImages = images.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            
        let batchDimensions = GraphicsMagickHelper.getBatchImageDimensions(
            imagePaths: validImages.map { $0.path },
            gmPath: gmPath
        )
            
        // STEP 2: Prepare batch file
        let batchFilePath = fileManager.temporaryDirectory
            .appendingPathComponent("me2comic_batch_\(UUID().uuidString).txt")
        defer { try? fileManager.removeItem(at: batchFilePath) }
            
        var batchCommands = ""
            
        // STEP 3: Process each image
        for imageFile in images {
            activeTasksQueue.sync { cancel = self.shouldCancelProcessing }
            if cancel { break }
                
            let filename = imageFile.lastPathComponent
            let filenameWithoutExt = imageFile.deletingPathExtension().lastPathComponent
            let outputBasePath = outputDir.appendingPathComponent(filenameWithoutExt).path
                
            // Get dimensions with batch-first fallback
            var dimensions: (width: Int, height: Int)?
            if let batchDim = batchDimensions[imageFile.path] {
                dimensions = batchDim
            } else {
                dimensions = GraphicsMagickHelper.getImageDimensions(
                    imagePath: imageFile.path,
                    gmPath: gmPath
                )
            }
                
            guard let dimensions = dimensions else {
                failedFiles.append(filename)
                continue
            }
                
            let (width, height) = dimensions
                
            if width < widthThreshold {
                // Single image processing
                let command = GraphicsMagickHelper.buildConvertCommand(
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
                // Split processing
                let cropWidth = width / 2
                    
                // Right half
                batchCommands.append(GraphicsMagickHelper.buildConvertCommand(
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
                ) + "\n")
                    
                // Left half
                batchCommands.append(GraphicsMagickHelper.buildConvertCommand(
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
                ) + "\n")
                    
                processedCount += 1
            }
        }
            
        // Early exit if cancelled or no commands
        guard !batchCommands.isEmpty, !cancel else {
            return processedCount
        }
            
        // STEP 4: Execute batch
        do {
            try batchCommands.write(to: batchFilePath, atomically: true, encoding: .utf8)
                
            let batchTask = Process()
            batchTask.executableURL = URL(fileURLWithPath: gmPath)
            batchTask.arguments = ["batch", "-stop-on-error", "off"]
                
            let pipes = (input: Pipe(), output: Pipe(), error: Pipe())
            batchTask.standardInput = pipes.input
            batchTask.standardOutput = pipes.output
            batchTask.standardError = pipes.error
                
            // Track task
            let managedTask = ManagedTask(process: batchTask)
            activeTasksQueue.async { self.activeTasks.append(managedTask) }
                
            try batchTask.run()
            try pipes.input.fileHandleForWriting.write(Data(contentsOf: batchFilePath))
            pipes.input.fileHandleForWriting.closeFile()
                
            batchTask.waitUntilExit()
            activeTasksQueue.async { self.activeTasks.removeAll { $0.id == managedTask.id } }
                
            // Handle errors
            if batchTask.terminationStatus != 0 {
                if let error = String(
                    data: pipes.error.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ), !error.isEmpty {
                    DispatchQueue.main.async {
                        self.logMessages.append("Batch failed: \(error)")
                    }
                }
                failedFiles.append(contentsOf: images.map { $0.lastPathComponent })
                return 0
            }
                
            return processedCount
        } catch {
            DispatchQueue.main.async {
                self.logMessages.append("Batch error: \(error.localizedDescription)")
            }
            return 0
        }
    }

    // Get all image files from a directory
    private func getImageFiles(_ directory: URL) -> [URL] {
        let fileManager = FileManager.default
        let imageExtensions = ["jpg", "jpeg", "png"]
        
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            return files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        } catch {
            return []
        }
    }
    
    // Split images into batches with configurable batch size
    private func splitIntoBatches(_ images: [URL], batchSize: Int) -> [[URL]] {
        var result: [[URL]] = []
        var currentBatch: [URL] = []
        
        // Pre-allocate capacity for better performance
        result.reserveCapacity(images.count / batchSize + 1)
        currentBatch.reserveCapacity(batchSize)
        
        for image in images {
            currentBatch.append(image)
            
            if currentBatch.count >= batchSize {
                result.append(currentBatch)
                currentBatch = []
                currentBatch.reserveCapacity(batchSize)
            }
        }
        
        if !currentBatch.isEmpty {
            result.append(currentBatch)
        }
        
        return result
    }
    
    // Validate batch size parameter, ensuring it's within valid range
    private func validateBatchSize(_ batchSizeStr: String) -> Int {
        guard let batchSize = Int(batchSizeStr), batchSize >= 1, batchSize <= 1000 else {
            DispatchQueue.main.async {
                self.logMessages.append(NSLocalizedString("InvalidBatchSize", comment: ""))
            }
            return 40 // Default value
        }
        return batchSize
    }
    
    // Thread-safe update of processed count
    private func updateProcessedCount(_ count: Int) {
        processedCountQueue.async {
            self.totalImagesProcessed += count
        }
    }
    
    // Format processing time for display
    private func formatProcessingTime(_ seconds: Int) -> String {
        if seconds < 60 {
            return String(format: NSLocalizedString("ProcessingTimeSeconds", comment: ""), seconds)
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return String(format: NSLocalizedString("ProcessingTimeMinutesSeconds", comment: ""), minutes, remainingSeconds)
        }
    }

    // Main processing function
    func processImages(inputDir: URL, outputDir: URL, parameters: ProcessingParameters) {
        // Validate parameters
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

        // Reset processing state
        resetProcessingState()

        // Log start with appropriate parameters
        logStartParameters(threshold, resize, qual, parameters.threadCount, radius, sigma, amount, unsharpThreshold, parameters.useGrayColorspace)

        // Verify GraphicsMagick
        guard verifyGraphicsMagick() else {
            isProcessing = false
            return
        }
        
        let fileManager = FileManager.default
        
        // Create output directory
        do {
            try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logMessages.append(String(format: NSLocalizedString("CannotCreateOutputDir", comment: ""), error.localizedDescription))
            isProcessing = false
            return
        }

        // Process in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard !self.shouldCancelProcessing else {
                DispatchQueue.main.async {
                    self.logMessages.append(NSLocalizedString("ProcessingCancelledNoStart", comment: ""))
                    self.isProcessing = false
                }
                return
            }

            self.processDirectories(inputDir: inputDir, outputDir: outputDir, parameters: parameters)
        }
    }
    
    // Reset processing state
    private func resetProcessingState() {
        activeTasksQueue.async(flags: .barrier) {
            self.shouldCancelProcessing = false
        }

        totalImagesProcessed = 0
        processingStartTime = Date()

        activeTasksQueue.async(flags: .barrier) {
            self.activeTasks.removeAll()
        }
    }
    
    // Log start parameters
    private func logStartParameters(_ threshold: Int, _ resize: Int, _ qual: Int, _ threadCount: Int,
                                    _ radius: Float, _ sigma: Float, _ amount: Float, _ unsharpThreshold: Float,
                                    _ useGrayColorspace: Bool)
    {
        if amount > 0 {
            logMessages.append(String(format: NSLocalizedString("StartProcessingWithUnsharp", comment: ""),
                                      threshold, resize, qual, threadCount, radius, sigma, amount, unsharpThreshold,
                                      NSLocalizedString(useGrayColorspace ? "GrayEnabled" : "GrayDisabled", comment: "")))
        } else {
            logMessages.append(String(format: NSLocalizedString("StartProcessingNoUnsharp", comment: ""),
                                      threshold, resize, qual, threadCount,
                                      NSLocalizedString(useGrayColorspace ? "GrayEnabled" : "GrayDisabled", comment: "")))
        }
    }
    
    // Verify GraphicsMagick installation
    private func verifyGraphicsMagick() -> Bool {
        // Verify GM using safe path detection
        guard let detectedPath = GraphicsMagickHelper.detectGMPathSafely(logHandler: { message in
            self.logMessages.append(message)
        }) else {
            return false
        }

        // Store valid GM path
        gmPath = detectedPath

        // Check GraphicsMagick version
        return GraphicsMagickHelper.verifyGraphicsMagick(gmPath: gmPath, logHandler: { message in
            self.logMessages.append(message)
        })
    }
    
    // Process directories
    private func processDirectories(inputDir: URL, outputDir: URL, parameters: ProcessingParameters) {
        let failedFilesQueue = DispatchQueue(label: "me2.comic.me2comic.failedFiles", attributes: [])
        let fileManager = FileManager.default

        do {
            // Get subdirectories
            let subdirectories = try fileManager.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { url in
                    guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                          let isDirectory = resourceValues.isDirectory
                    else { return false }
                    return isDirectory
                }
            
            if subdirectories.isEmpty {
                DispatchQueue.main.async {
                    self.logMessages.append(NSLocalizedString("NoSubdirectories", comment: ""))
                    self.isProcessing = false
                }
                return
            }
            
            // Process all subdirectories
            let allFailedFiles = processSubdirectories(
                subdirectories: subdirectories,
                outputDir: outputDir,
                parameters: parameters,
                failedFilesQueue: failedFilesQueue
            )
            
            // Finalize processing
            finalizeProcessing(subdirectories: subdirectories, failedFiles: allFailedFiles)
            
        } catch {
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("ProcessingFailed", comment: ""), error.localizedDescription))
                self.isProcessing = false
            }
        }
    }
    
    // Process all subdirectories
    private func processSubdirectories(
        subdirectories: [URL],
        outputDir: URL,
        parameters: ProcessingParameters,
        failedFilesQueue: DispatchQueue
    ) -> [String] {
        // Parse parameters once
        guard let threshold = Int(parameters.widthThreshold),
              let resize = Int(parameters.resizeHeight),
              let qual = Int(parameters.quality),
              let radius = Float(parameters.unsharpRadius),
              let sigma = Float(parameters.unsharpSigma),
              let amount = Float(parameters.unsharpAmount),
              let unsharpThreshold = Float(parameters.unsharpThreshold)
        else { return [] }
        
        // Create a dispatch group for all tasks
        let processingGroup = DispatchGroup()
        
        // Create a semaphore to limit concurrent tasks
        let semaphore = DispatchSemaphore(value: parameters.threadCount)
        
        // Create a concurrent queue for processing
        let processingQueue = DispatchQueue(label: "me2.comic.me2comic.processing",
                                            qos: .userInitiated,
                                            attributes: .concurrent)
        
        // Collect all batches from all subdirectories
        var allBatches: [(subdirName: String, outputDir: URL, images: [URL])] = []
        
        // Thread-safe collection for failed files
        let failedFiles = ThreadSafeArray<String>(queue: failedFilesQueue)
        
        // Prepare all batches and pre-fetch dimensions
        prepareAllBatches(
            subdirectories: subdirectories,
            outputDir: outputDir,
            parameters: parameters,
            allBatches: &allBatches
        )
        
        // Process all batches in parallel
        processAllBatches(
            allBatches: allBatches,
            threshold: threshold,
            resize: resize,
            qual: qual,
            radius: radius,
            sigma: sigma,
            amount: amount,
            unsharpThreshold: unsharpThreshold,
            useGrayColorspace: parameters.useGrayColorspace,
            processingGroup: processingGroup,
            semaphore: semaphore,
            processingQueue: processingQueue,
            failedFiles: failedFiles
        )
        
        // Wait for all processing to complete
        processingGroup.wait()
        
        // Return the collected failed files
        return failedFiles.getAll()
    }
    
    // Prepare all batches for processing
    private func prepareAllBatches(
        subdirectories: [URL],
        outputDir: URL,
        parameters: ProcessingParameters,
        allBatches: inout [(subdirName: String, outputDir: URL, images: [URL])]
    ) {
        let fileManager = FileManager.default
        
        for subdirectory in subdirectories {
            // Check cancellation flag
            var cancel = false
            activeTasksQueue.sync {
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
            
            // Get all image files in this subdirectory
            let imageFiles = getImageFiles(subdirectory)
            
            if imageFiles.isEmpty {
                DispatchQueue.main.async {
                    self.logMessages.append(String(format: NSLocalizedString("NoImagesInDir", comment: ""), subdirName))
                }
                continue
            }
            
            // Log processing start for subdirectory
            DispatchQueue.main.async {
                self.logMessages.append(String(format: NSLocalizedString("StartProcessingSubdir", comment: ""), subdirName))
            }
            
            // Split into batches using user-defined batch size
            let batchSize = validateBatchSize(parameters.batchSize)
            let batches = splitIntoBatches(imageFiles, batchSize: batchSize)
            
            // Add all batches to the collection
            for batch in batches {
                allBatches.append((subdirName, outputSubdir, batch))
            }
        }
    }
    
    // Process all batches in parallel
    private func processAllBatches(
        allBatches: [(subdirName: String, outputDir: URL, images: [URL])],
        threshold: Int,
        resize: Int,
        qual: Int,
        radius: Float,
        sigma: Float,
        amount: Float,
        unsharpThreshold: Float,
        useGrayColorspace: Bool,
        processingGroup: DispatchGroup,
        semaphore: DispatchSemaphore,
        processingQueue: DispatchQueue,
        failedFiles: ThreadSafeArray<String>
    ) {
        for batch in allBatches {
            // Check cancellation flag
            var cancel = false
            activeTasksQueue.sync {
                cancel = self.shouldCancelProcessing
            }
            if cancel { break }
            
            processingGroup.enter()
            semaphore.wait() // Limit concurrent tasks
            
            processingQueue.async {
                defer {
                    semaphore.signal() // Release semaphore
                    processingGroup.leave()
                }
                
                // Check cancellation flag again
                var cancel = false
                self.activeTasksQueue.sync {
                    cancel = self.shouldCancelProcessing
                }
                if cancel { return }
                
                var localFailedFiles: [String] = []
                
                // Process this batch
                let processed = self.processBatchImages(
                    images: batch.images,
                    outputDir: batch.outputDir,
                    widthThreshold: threshold,
                    resizeHeight: resize,
                    quality: qual,
                    unsharpRadius: radius,
                    unsharpSigma: sigma,
                    unsharpAmount: amount,
                    unsharpThreshold: unsharpThreshold,
                    useGrayColorspace: useGrayColorspace,
                    failedFiles: &localFailedFiles
                )
                
                // Update processed count
                if processed > 0 {
                    self.updateProcessedCount(processed)
                }
                
                // Update failed files list
                if !localFailedFiles.isEmpty {
                    failedFiles.append(contentsOf: localFailedFiles)
                }
            }
        }
    }
    
    // Finalize processing and report results
    private func finalizeProcessing(subdirectories: [URL], failedFiles: [String]) {
        // Check if processing was cancelled
        var wasCancelled = false
        activeTasksQueue.sync {
            wasCancelled = self.shouldCancelProcessing
        }
        
        // Get final processed count
        var finalProcessedCount = 0
        processedCountQueue.sync {
            finalProcessedCount = self.totalImagesProcessed
        }
        
        // Calculate processing time
        let processingTime = Int(Date().timeIntervalSince(processingStartTime ?? Date()))
        let timeMessage = formatProcessingTime(processingTime)
        
        DispatchQueue.main.async {
            if wasCancelled {
                self.logMessages.append(NSLocalizedString("ProcessingStopped", comment: ""))
            } else {
                // Log subdirectory completion for all subdirectories
                for subdirectory in subdirectories {
                    self.logMessages.append(String(format: NSLocalizedString("ProcessedSubdir", comment: ""), subdirectory.lastPathComponent))
                }
                
                // Report failed files if any
                if !failedFiles.isEmpty {
                    self.logMessages.append(String(format: NSLocalizedString("FailedFiles", comment: ""), failedFiles.count))
                    for file in failedFiles.prefix(10) { // Limit to first 10 files
                        self.logMessages.append("- \(file)")
                    }
                    if failedFiles.count > 10 {
                        self.logMessages.append(String(format: "... %d more", failedFiles.count - 10))
                    }
                }
                
                // Report total processed
                self.logMessages.append(String(format: NSLocalizedString("TotalImagesProcessed", comment: ""), finalProcessedCount))
                self.logMessages.append(timeMessage)
                self.logMessages.append(NSLocalizedString("ProcessingComplete", comment: ""))
                
                // Send notification
                self.sendCompletionNotification(totalProcessed: finalProcessedCount, failedCount: failedFiles.count)
            }
            
            self.isProcessing = false
        }
    }
    
    // Send notification when processing is complete
    private func sendCompletionNotification(totalProcessed: Int, failedCount: Int) {
        let center = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("ProcessingCompleteTitle", comment: "")
        
        if failedCount > 0 {
            content.body = String(format: NSLocalizedString("ProcessingCompleteWithFailures", comment: ""), totalProcessed, failedCount)
        } else {
            content.body = String(format: NSLocalizedString("ProcessingCompleteSuccess", comment: ""), totalProcessed)
        }
        
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
