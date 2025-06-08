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
}
