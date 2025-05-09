//
//  ImageProcessorView.swift
//  Me2Comic
//
//  Created by Me2 on 2025/4/27.
//

import Foundation
import SwiftUI
import UserNotifications

// Active tasks list (SwiftUI state)
struct ManagedTask: Identifiable {
    let id = UUID()
    let process: Process
}

struct ImageProcessorView: View {
    @State private var inputDirectory: URL?
    @State private var outputDirectory: URL?
    @State private var logMessage: String = ""
    @State private var isProcessing: Bool = false
    @State private var shouldCancelProcessing: Bool = false
    @State private var widthThreshold: String = "3000"
    @State private var resizeHeight: String = "1648"
    @State private var quality: String = "85"
    @State private var threadCount: Int = 2
    @State private var unsharpRadius: String = "1.5"
    @State private var useGrayColorspace: Bool = false
    @State private var unsharpSigma: String = "1"
    @State private var unsharpAmount: String = "0.7"
    @State private var unsharpThreshold: String = "0.02"
    @State private var totalImagesProcessed: Int = 0
    @State private var processingStartTime: Date?
    @State private var activeTasks: [ManagedTask] = []
    @State private var gmPath: String = ""

    private func detectGMPathViaWhich() -> String? {
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["gm"]
    
        var env = ProcessInfo.processInfo.environment
        let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let originalPath = env["PATH"] ?? ""
        env["PATH"] = homebrewPaths.joined(separator: ":") + ":" + originalPath
        whichTask.environment = env
    
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = pipe // Capture stderr
    
        do {
            try whichTask.run()
            whichTask.waitUntilExit()
        
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard whichTask.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty
            else {
                // Read error message from the pipe
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                appendLog(String(format: NSLocalizedString("WhichGMException", comment: ""), errorMessage) + "\n")
                return nil
            }
            return output
        } catch {
            appendLog(NSLocalizedString("WhichGMFailed", comment: "") + "\n")
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            LeftPanelView()
            
            GradientDividerView()

            VStack(spacing: 25) {
                Spacer().frame(height: 5)
                
                DirectoryButtonView(
                    title: String(format: NSLocalizedString("Input Directory", comment: ""),
                                  inputDirectory?.path ?? NSLocalizedString("Input Directory Placeholder", comment: "")),
                    action: { selectInputDirectory() },
                    isProcessing: isProcessing
                )
                .padding(.top, -11)

                DirectoryButtonView(
                    title: String(format: NSLocalizedString("Output Directory", comment: ""),
                                  outputDirectory?.path ?? NSLocalizedString("Output Directory Placeholder", comment: "")),
                    action: { selectOutputDirectory() },
                    isProcessing: isProcessing
                )
                .padding(.bottom, 10)
                
                // 设置
                HStack(alignment: .top, spacing: 16) {
                    SettingsPanelView(
                        widthThreshold: $widthThreshold,
                        resizeHeight: $resizeHeight,
                        quality: $quality,
                        threadCount: $threadCount,
                        unsharpRadius: $unsharpRadius,
                        unsharpSigma: $unsharpSigma,
                        unsharpAmount: $unsharpAmount,
                        unsharpThreshold: $unsharpThreshold,
                        useGrayColorspace: $useGrayColorspace,
                        isProcessing: isProcessing
                    )

                    // 参数说明区域
                    ParameterDescriptionView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 1)
                .fixedSize(horizontal: false, vertical: true)
                .background(.panelBackground)

                // Go按钮
                ActionButtonView(isProcessing: isProcessing) {
                    if isProcessing {
                        stopProcessing()
                    } else {
                        processImages()
                    }
                }
                .disabled(!isProcessing && (inputDirectory == nil || outputDirectory == nil))

                // 日志窗口
                ScrollViewReader { proxy in
                    LogView(logMessage: logMessage)
                        .onChange(of: logMessage) { _ in
                            withAnimation {
                                proxy.scrollTo("log", anchor: .bottom)
                            }
                        }
                }
                .padding(.bottom, 20)
    
                //  删除 Spacer() 否则 padding 无效
            }
            .padding(.horizontal)
        }
        .frame(minWidth: 996, minHeight: 735)
        .background(.panelBackground)
    }

    private func selectInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
    
        if panel.runModal() == .OK, let url = panel.url {
            inputDirectory = url
            appendLog(String(format: NSLocalizedString("SelectedInputDir", comment: ""), url.path) + "\n")
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
    
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            appendLog(String(format: NSLocalizedString("SelectedOutputDir", comment: ""), url.path) + "\n")
        }
    }
    
    private func appendLog(_ message: String) {
        DispatchQueue.main.async {
            logMessage += message // 直接追加到主日志
        }
    }

    // 停止函数
    private func stopProcessing() {
        shouldCancelProcessing = true
 
        DispatchQueue.global(qos: .userInitiated).async {
            for task in activeTasks {
                if task.process.isRunning {
                    task.process.terminate()
                    task.process.waitUntilExit()
                }
            }

            DispatchQueue.main.async {
                activeTasks.removeAll()
                appendLog(NSLocalizedString("ProcessingStopped", comment: "") + "\n")
                isProcessing = false
            }
        }
    }
    
    private func processImages() {
        guard let inputDir = inputDirectory, let outputDir = outputDirectory else {
            appendLog(NSLocalizedString("NoInputOrOutputDir", comment: "") + "\n")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                DispatchQueue.main.async {
                    appendLog(String(format: NSLocalizedString("NotificationPermissionFailed", comment: ""), error.localizedDescription) + "\n")
                }
            } else if !granted {
                DispatchQueue.main.async {
                    appendLog(NSLocalizedString("NotificationPermissionNotGranted", comment: "") + "\n")
                }
            }
        }
    
        // 验证宽度阈值
        guard let threshold = Int(widthThreshold), threshold > 0 else {
            appendLog(NSLocalizedString("InvalidWidthThreshold", comment: "") + "\n")
            isProcessing = false
            return
        }

        // 验证 resize 高度
        guard let resize = Int(resizeHeight), resize > 0 else {
            appendLog(NSLocalizedString("InvalidResizeHeight", comment: "") + "\n")
            isProcessing = false
            return
        }

        // 验证输出质量
        guard let qual = Int(quality), qual >= 1, qual <= 100 else {
            appendLog(NSLocalizedString("InvalidOutputQuality", comment: "") + "\n")
            isProcessing = false
            return
        }

        // 验证 unsharp 参数
        guard let radius = Float(unsharpRadius), radius >= 0,
              let sigma = Float(unsharpSigma), sigma >= 0,
              let amount = Float(unsharpAmount), amount >= 0,
              let unsharpThreshold = Float(unsharpThreshold), unsharpThreshold >= 0
        else {
            appendLog(NSLocalizedString("InvalidUnsharpParameters", comment: "") + "\n")
            isProcessing = false
            return
        }

        isProcessing = true
        shouldCancelProcessing = false // 重置取消标志
        totalImagesProcessed = 0
        activeTasks.removeAll()
        processingStartTime = Date() // 计时
        if amount > 0 {
            appendLog(String(format: NSLocalizedString("StartProcessingWithUnsharp", comment: ""),
                             threshold, resize, qual, threadCount, radius, sigma, amount, unsharpThreshold,
                             NSLocalizedString(useGrayColorspace ? "GrayEnabled" : "GrayDisabled", comment: "")) + "\n")
        } else {
            appendLog(String(format: NSLocalizedString("StartProcessingNoUnsharp", comment: ""),
                             threshold, resize, qual, threadCount) + "\n")
        }

        // 检查 GraphicsMagick
        guard let detectedPath = detectGMPathViaWhich() else {
            DispatchQueue.main.async {
                appendLog(NSLocalizedString("CannotRunGraphicsMagick", comment: "") + "\n")
                isProcessing = false
            }
            return
        }
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
                DispatchQueue.main.async {
                    appendLog(String(format: NSLocalizedString("GraphicsMagickRunFailed", comment: ""), outputMessage) + "\n")
                    isProcessing = false
                }
                return
            } else {
                DispatchQueue.main.async {
                    appendLog(String(format: NSLocalizedString("GraphicsMagickVersion", comment: ""), outputMessage) + "\n")
                }
            }
        } catch {
            DispatchQueue.main.async {
                appendLog(String(format: NSLocalizedString("CannotRunGraphicsMagick", comment: ""), error.localizedDescription) + "\n")
                isProcessing = false
            }
            return
        }

        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            DispatchQueue.main.async {
                appendLog(String(format: NSLocalizedString("CannotCreateOutputDir", comment: ""), error.localizedDescription) + "\n")
                isProcessing = false
            }
            return
        }
    
        // 异步处理图片
        DispatchQueue.global(qos: .userInitiated).async {
            guard !shouldCancelProcessing else {
                DispatchQueue.main.async {
                    appendLog(NSLocalizedString("ProcessingCancelledNoStart", comment: "") + "\n")
                    isProcessing = false
                }
                return
            }
    
            let fileManager = FileManager.default
            let imageExtensions = ["jpg", "jpeg", "png"]
            var failedFiles: [String] = []
    
            // 创建并发队列，限制最大并发数
            let processingQueue = DispatchQueue(label: "me2.comic.me2comic.processing", qos: .userInitiated, attributes: [.concurrent], target: .global(qos: .userInitiated))
            let group = DispatchGroup() // 使用线程组跟踪所有任务
            let semaphore = DispatchSemaphore(value: threadCount) // 限制并发线程数
    
            do {
                let subdirectories = try fileManager.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: nil)
                for subdirectory in subdirectories {
                    guard !shouldCancelProcessing else {
                        DispatchQueue.main.async {
                            appendLog(NSLocalizedString("ProcessingCancelledSubdir", comment: "") + "\n")
                            isProcessing = false
                        }
                        break
                    }
            
                    guard subdirectory.hasDirectoryPath else { continue }
                    let subdirectoryName = subdirectory.lastPathComponent
                    let subOutputDir = outputDir.appendingPathComponent(subdirectoryName)
            
                    do {
                        try fileManager.createDirectory(at: subOutputDir, withIntermediateDirectories: true, attributes: nil)
                        DispatchQueue.main.async {
                            appendLog(String(format: NSLocalizedString("StartProcessingSubdir", comment: ""), subdirectoryName) + "\n")
                        }
                
                        var isSubdirectoryCompleted = true
                        let files = try fileManager.contentsOfDirectory(at: subdirectory, includingPropertiesForKeys: nil)
                        for file in files {
                            guard !shouldCancelProcessing else {
                                DispatchQueue.main.async {
                                    appendLog(NSLocalizedString("ProcessingCancelledFiles", comment: "") + "\n")
                                    isProcessing = false
                                }
                                isSubdirectoryCompleted = false
                                break
                            }
                    
                            guard imageExtensions.contains(file.pathExtension.lowercased()) else { continue }
                    
                            // 使用信号量控制并发
                            group.enter()
                            semaphore.wait()
                            processingQueue.async {
                                defer {
                                    semaphore.signal()
                                    group.leave()
                                }
                        
                                guard !shouldCancelProcessing else { return }
                                processImage(file, outputDir: subOutputDir, failedFiles: &failedFiles, widthThreshold: threshold, resizeHeight: resize, quality: qual, unsharpRadius: radius, unsharpSigma: sigma, unsharpAmount: amount, unsharpThreshold: unsharpThreshold)
                                DispatchQueue.main.async {
                                    totalImagesProcessed += 1
                                }
                            }
                        }
                        if isSubdirectoryCompleted && !shouldCancelProcessing {
                            DispatchQueue.main.async {
                                appendLog(String(format: NSLocalizedString("CompleteProcessingSubdir", comment: ""), subdirectoryName) + "\n")
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            appendLog(String(format: NSLocalizedString("SubdirProcessingFailed", comment: ""), subdirectoryName, error.localizedDescription) + "\n")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    appendLog(String(format: NSLocalizedString("CannotReadInputDir", comment: ""), error.localizedDescription) + "\n")
                }
            }

            // 等待所有任务完成
            group.notify(queue: .main) {
                if !shouldCancelProcessing {
                    if !failedFiles.isEmpty {
                        appendLog(NSLocalizedString("FailedFilesList", comment: "") + "\n")
                        failedFiles.forEach { appendLog("- \($0)\n") }
                    }
                    appendLog(String(format: NSLocalizedString("TotalImagesProcessed", comment: ""), totalImagesProcessed) + "\n")
                    // 计时
                    if let startTime = processingStartTime {
                        let elapsedTime = Date().timeIntervalSince(startTime)
                        if elapsedTime < 60 {
                            appendLog(String(format: NSLocalizedString("ProcessingTimeSeconds", comment: ""), Int(elapsedTime)) + "\n")
                        } else {
                            appendLog(String(format: NSLocalizedString("ProcessingTimeMinutes", comment: ""), Int(elapsedTime / 60)) + "\n")
                        }
                    }
                    appendLog(NSLocalizedString("ProcessingCompleted", comment: "") + "\n")
        
                    let content = UNMutableNotificationContent()
                    content.title = NSLocalizedString("TaskCompletedTitle", comment: "")
                    content.body = NSLocalizedString("TaskCompletedBody", comment: "")
                    content.sound = UNNotificationSound.default
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                isProcessing = false
                activeTasks.removeAll()
            }
        }
    }
    
    // 单张图片处理方法
    private func processImage(_ imageURL: URL, outputDir: URL, failedFiles: inout [String], widthThreshold: Int, resizeHeight: Int, quality: Int, unsharpRadius: Float, unsharpSigma: Float, unsharpAmount: Float, unsharpThreshold: Float) {
        guard !shouldCancelProcessing else {
            DispatchQueue.main.async {
                appendLog(String(format: NSLocalizedString("CancelProcessingImage", comment: ""), imageURL.lastPathComponent) + "\n")
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
                    appendLog(String(format: NSLocalizedString("CannotGetImageDimensions", comment: ""), filename) + "\n")
                }
                failedFiles.append(filename)
                return
            }

            let dimensions = output.split(separator: " ").compactMap { Int($0) }
            guard dimensions.count == 2 else {
                DispatchQueue.main.async {
                    appendLog(String(format: NSLocalizedString("CannotGetImageDimensions", comment: ""), filename) + "\n")
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
    
                DispatchQueue.main.async {
                    activeTasks.append(ManagedTask(process: magickTask))
                }
    
                do {
                    try magickTask.run()
                    magickTask.waitUntilExit()
        
                    if magickTask.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                        failedFiles.append(filename)
                        DispatchQueue.main.async {
                            appendLog(String(format: NSLocalizedString("ProcessSingleImageFailed", comment: ""), filename, errorMessage) + "\n")
                        }
                    }
                } catch {
                    failedFiles.append(filename)
                    DispatchQueue.main.async {
                        appendLog(String(format: NSLocalizedString("ProcessSingleImageFailed", comment: ""), filename, error.localizedDescription) + "\n")
                    }
                }

                // 裁切
            } else {
                let cropWidth = width / 2
                let outputFile1 = "\(outputPath)-1.jpg"
                var arguments1 = [
                    "convert",
                    imageURL.path,
                    "-crop", "\(cropWidth)x\(height)+\(cropWidth)+0", // 右半部分 从宽度cropWidth位置开始裁剪
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
    
                DispatchQueue.main.async {
                    activeTasks.append(ManagedTask(process: magickTask1))
                }
    
                try magickTask1.run()
                magickTask1.waitUntilExit()
    
                if magickTask1.terminationStatus != 0 {
                    let errorData = errorPipe1.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                    DispatchQueue.main.async {
                        appendLog(String(format: NSLocalizedString("ProcessImagePart1Failed", comment: ""), filename, filenameNoExt, errorMessage) + "\n")
                    }
                    failedFiles.append(filename)
                }

                guard !shouldCancelProcessing else {
                    DispatchQueue.main.async {
                        appendLog(String(format: NSLocalizedString("CancelProcessImagePart2", comment: ""), filename) + "\n")
                    }
                    return
                }

                let outputFile2 = "\(outputPath)-2.jpg"
                var arguments2 = [
                    "convert",
                    imageURL.path,
                    "-crop", "\(cropWidth)x\(height)+0+0", // 左半部分
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
    
                DispatchQueue.main.async {
                    activeTasks.append(ManagedTask(process: magickTask2))
                }
    
                try magickTask2.run()
                magickTask2.waitUntilExit()
    
                if magickTask2.terminationStatus != 0 {
                    let errorData = errorPipe2.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? NSLocalizedString("UnknownError", comment: "")
                    DispatchQueue.main.async {
                        appendLog(String(format: NSLocalizedString("ProcessImagePart2Failed", comment: ""), filename, filenameNoExt, errorMessage) + "\n")
                    }
                    failedFiles.append(filename)
                }
            }
        } catch {
            DispatchQueue.main.async {
                appendLog(String(format: NSLocalizedString("ProcessImageFailed", comment: ""), filename, error.localizedDescription) + "\n")
            }
            failedFiles.append(filename)
        }
    }
}

struct ImageProcessorView_Previews: PreviewProvider {
    static var previews: some View {
        ImageProcessorView()
    }
}
