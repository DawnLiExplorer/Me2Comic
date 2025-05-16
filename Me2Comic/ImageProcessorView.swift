//
//  ImageProcessorView.swift
//  Me2Comic
//
//  Created by Me2 on 2025/4/27.
//

import AppKit
import SwiftUI
import UserNotifications

struct ImageProcessorView: View {
    @State private var inputDirectory: URL?
    @State private var outputDirectory: URL?
    @State private var widthThreshold: String = "3000"
    @State private var resizeHeight: String = "1648"
    @State private var quality: String = "85"
    @State private var threadCount: Int = 2
    @State private var unsharpRadius: String = "1.5"
    @State private var useGrayColorspace: Bool = true
    @State private var unsharpSigma: String = "1"
    @State private var unsharpAmount: String = "0.7"
    @State private var unsharpThreshold: String = "0.02"

    @ObservedObject private var processor = ImageProcessor()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            LeftPanelView() // Left panel

            GradientDividerView() // Divider line

            VStack(spacing: 25) {
                Spacer().frame(height: 5)

                // Input Dir Button
                DirectoryButtonView(
                    title: String(format: NSLocalizedString("Input Directory", comment: ""),
                                  inputDirectory?.path ?? NSLocalizedString("Input Directory Placeholder", comment: "")),
                    action: { selectInputDirectory() },
                    isProcessing: processor.isProcessing,
                    openAction: nil,
                    showOpenButton: false
                )
                .padding(.top, -11)

                // Output Dir Button
                DirectoryButtonView(
                    title: String(format: NSLocalizedString("Output Directory", comment: ""),
                                  outputDirectory?.path ?? NSLocalizedString("Output Directory Placeholder", comment: "")),
                    action: { selectOutputDirectory() },
                    isProcessing: processor.isProcessing,
                    openAction: { // Open in Finder
                        if let url = outputDirectory {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    showOpenButton: outputDirectory != nil
                )
                .padding(.bottom, 10)

                // Parameters panel
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
                        isProcessing: processor.isProcessing
                    )

                    // Parameters description
                    ParameterDescriptionView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 1)
                .fixedSize(horizontal: false, vertical: true)
                .background(.panelBackground)

                // Go/Stop
                ActionButtonView(isProcessing: processor.isProcessing) {
                    if processor.isProcessing {
                        processor.stopProcessing()
                    } else {
                        processImages()
                    }
                }
                .disabled(!processor.isProcessing && (inputDirectory == nil || outputDirectory == nil))

                // Log console
                ScrollViewReader { _ in
                    DecoratedView(content: LogTextView(text: processor.logMessages.joined(separator: "\n")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 15)
                }
                .padding(.bottom, 5)
            }
            .padding(.horizontal)
        }
        .frame(minWidth: 996, minHeight: 735) // Sets min window size
        .background(.panelBackground)
        .onAppear {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error = error {
                    DispatchQueue.main.async {
                        processor.logMessages.append(String(format: NSLocalizedString("NotificationPermissionFailed", comment: ""), error.localizedDescription))
                    }
                } else if !granted {
                    DispatchQueue.main.async {
                        processor.logMessages.append(NSLocalizedString("NotificationPermissionNotGranted", comment: ""))
                    }
                }
            }
        }
    }

    // Directory Selection
    private func selectInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            inputDirectory = url
            processor.logMessages.append(String(format: NSLocalizedString("SelectedInputDir", comment: ""), url.path))
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            processor.logMessages.append(String(format: NSLocalizedString("SelectedOutputDir", comment: ""), url.path))
        }
    }

    private func processImages() {
        guard let inputDir = inputDirectory, let outputDir = outputDirectory else {
            processor.logMessages.append(NSLocalizedString("NoInputOrOutputDir", comment: ""))
            return
        }

        let parameters = ProcessingParameters(
            widthThreshold: widthThreshold,
            resizeHeight: resizeHeight,
            quality: quality,
            threadCount: threadCount,
            unsharpRadius: unsharpRadius,
            unsharpSigma: unsharpSigma,
            unsharpAmount: unsharpAmount,
            unsharpThreshold: unsharpThreshold,
            useGrayColorspace: useGrayColorspace
        )
        processor.processImages(inputDir: inputDir, outputDir: outputDir, parameters: parameters)
    }
}

// NSViewRepresentable wrapper for NSTextView
struct LogTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = NSColor(.textSecondary)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scrollToEndOfDocument(nil)
        }
    }
}

struct ImageProcessorView_Previews: PreviewProvider {
    static var previews: some View {
        ImageProcessorView()
    }
}
