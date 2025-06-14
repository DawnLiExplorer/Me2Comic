//
//  GraphicsMagickHelper.swift
//  Me2Comic
//
//  Created by Me2 on 2025/6/8.
//

import Foundation

/// Helper class for GraphicsMagick operations
class GraphicsMagickHelper {
    /// Safely detect GraphicsMagick executable path with predefined paths
    /// - Returns: Path to GraphicsMagick executable if found, nil otherwise
    static func detectGMPathSafely(logHandler: (String) -> Void) -> String? {
        // First check known safe paths
        let knownPaths = ["/opt/homebrew/bin/gm", "/usr/local/bin/gm", "/usr/bin/gm"]

        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to which command if known paths don't exist
        return detectGMPathViaWhich(logHandler: logHandler)
    }

    /// Detect GraphicsMagick executable path using which command
    /// - Parameter logHandler: Closure to handle log messages
    /// - Returns: Path to GraphicsMagick executable if found, nil otherwise
    private static func detectGMPathViaWhich(logHandler: (String) -> Void) -> String? {
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
        whichTask.standardError = pipe

        do {
            try whichTask.run()
            whichTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard whichTask.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty
            else {
                // Simplified error message
                logHandler(NSLocalizedString("GMNotFoundViaWhich", comment: "Cannot find gm via `which`"))
                return nil
            }
            return output
        } catch {
            logHandler(NSLocalizedString("GMWhichCommandFailed", comment: "`which gm` command failed"))
            return nil
        }
    }

    /// Verify GraphicsMagick installation and get version
    /// - Parameters:
    ///   - gmPath: Path to GraphicsMagick executable
    ///   - logHandler: Closure to handle log messages
    /// - Returns: True if GraphicsMagick is installed and working, false otherwise
    static func verifyGraphicsMagick(gmPath: String, logHandler: (String) -> Void) -> Bool {
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
                logHandler(NSLocalizedString("GMExecutionFailed", comment: "gm command failed to run properly"))
                return false
            } else {
                logHandler(String(format: NSLocalizedString("GraphicsMagickVersion", comment: ""), outputMessage))
            }
        } catch {
            logHandler(NSLocalizedString("GMExecutionException", comment: "Exception thrown when trying to run gm"))
            return false
        }

        return true
    }

    /// Properly escape path for shell command
    /// - Parameter path: Path to escape
    /// - Returns: Escaped path safe for shell commands
    static func escapePathForShell(_ path: String) -> String {
        // Replace backslashes with double backslashes
        var escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")

        // Replace double quotes with escaped double quotes
        escapedPath = escapedPath.replacingOccurrences(of: "\"", with: "\\\"")

        // Wrap in double quotes to handle spaces and special characters
        return "\"\(escapedPath)\""
    }

    /// Generate GraphicsMagick convert command
    /// - Parameters:
    ///   - inputPath: Path to input image
    ///   - outputPath: Path to output image
    ///   - cropParams: Optional crop parameters
    ///   - resizeHeight: Height to resize to
    ///   - quality: JPEG quality (1-100)
    ///   - unsharpRadius: Unsharp mask radius
    ///   - unsharpSigma: Unsharp mask sigma
    ///   - unsharpAmount: Unsharp mask amount
    ///   - unsharpThreshold: Unsharp mask threshold
    ///   - useGrayColorspace: Whether to convert to grayscale
    /// - Returns: Complete GraphicsMagick command string
    static func buildConvertCommand(
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

    /// Get image dimensions using GraphicsMagick
    /// - Parameters:
    ///   - imagePath: Path to the image
    ///   - gmPath: Path to GraphicsMagick executable
    /// - Returns: Tuple containing width and height if successful, nil otherwise
    static func getImageDimensions(imagePath: String, gmPath: String) -> (width: Int, height: Int)? {
        let dimensionsTask = Process()
        dimensionsTask.executableURL = URL(fileURLWithPath: gmPath)
        dimensionsTask.arguments = ["identify", "-format", "%w %h", imagePath]

        let pipe = Pipe()
        dimensionsTask.standardOutput = pipe
        dimensionsTask.standardError = pipe

        do {
            try dimensionsTask.run()
            dimensionsTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard dimensionsTask.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty
            else {
                return nil
            }

            let dimensions = output.split(separator: " ")
            guard dimensions.count == 2,
                  let width = Int(dimensions[0]),
                  let height = Int(dimensions[1])
            else {
                return nil
            }

            return (width: width, height: height)
        } catch {
            return nil
        }
    }

    /// Get dimensions for multiple images in a single gm identify call
    /// - Parameters:
    ///   - imagePaths: Array of image file paths
    ///   - gmPath: Path to GraphicsMagick executable
    /// - Returns: Dictionary mapping image paths to their dimensions
    static func getBatchImageDimensions(imagePaths: [String], gmPath: String) -> [String: (width: Int, height: Int)] {
        guard !imagePaths.isEmpty else { return [:] }

        let dimensionsTask = Process()
        dimensionsTask.executableURL = URL(fileURLWithPath: gmPath)

        // Use tab as delimiter
        var arguments = ["identify", "-format", "%f\t%w\t%h\n"]
        arguments.append(contentsOf: imagePaths)
        dimensionsTask.arguments = arguments

        let pipe = Pipe()
        dimensionsTask.standardOutput = pipe
        dimensionsTask.standardError = pipe

        do {
            try dimensionsTask.run()
            dimensionsTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard dimensionsTask.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8),
                  !output.isEmpty
            else {
                return [:]
            }

            var result: [String: (width: Int, height: Int)] = [:]

            // Create a mapping from filename to full paths to handle duplicate filenames
            var filenameToPathsMap: [String: [String]] = [:]
            for imagePath in imagePaths {
                let filename = URL(fileURLWithPath: imagePath).lastPathComponent
                if filenameToPathsMap[filename] == nil {
                    filenameToPathsMap[filename] = []
                }
                filenameToPathsMap[filename]?.append(imagePath)
            }

            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.isEmpty { continue }

                // Split by tab character
                let components = trimmedLine.components(separatedBy: "\t")
                guard components.count == 3,
                      let width = Int(components[1]),
                      let height = Int(components[2])
                else { continue }

                let filename = components[0]

                // Match the path precisely
                if let possiblePaths = filenameToPathsMap[filename] {
                    if possiblePaths.count == 1 {
                        // Unique filename, match directly
                        result[possiblePaths[0]] = (width: width, height: height)
                    } else {
                        // Multiple identical filenames, require more precise matching
                        // Since gm identify returns only the filename, match the first unmatched path in order
                        for path in possiblePaths {
                            if result[path] == nil {
                                result[path] = (width: width, height: height)
                                break
                            }
                        }
                    }
                }
            }

            return result
        } catch {
            return [:]
        }
    }
}
