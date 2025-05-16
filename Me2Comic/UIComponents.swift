//
//  UIComponents.swift
//  Me2Comic
//
//  Created by Me2 on 2025/5/3.
//

import AppKit
import SwiftUI

// 输入输出目录
struct DirectoryButtonView: View {
    let title: String
    let action: () -> Void
    let isProcessing: Bool
    let openAction: (() -> Void)?
    let showOpenButton: Bool

    @State private var isHovered: Bool = false
    @State private var isMainButtonHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                Text(title)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.backgroundPrimary.opacity(isProcessing ? 0.3 : 1))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.accent.opacity(0.5), lineWidth: 1)
                    .opacity(isMainButtonHovered && !isProcessing ? 1 : 0)
            )
            .onHover { hovering in
                isMainButtonHovered = hovering
            }

            if showOpenButton && !isProcessing {
                Button(action: openAction ?? {}) {
                    Text(NSLocalizedString("Open", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.backgroundPrimary)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.accent.opacity(0.5), lineWidth: 1)
                        .opacity(isHovered ? 1 : 0)
                )
                .onHover { hovering in
                    isHovered = hovering
                }
            }
        }
    }
}

// 设置区视图
struct SettingsPanelView: View {
    @Binding var widthThreshold: String
    @Binding var resizeHeight: String
    @Binding var quality: String
    @Binding var threadCount: Int
    @Binding var unsharpRadius: String
    @Binding var unsharpSigma: String
    @Binding var unsharpAmount: String
    @Binding var unsharpThreshold: String
    @Binding var useGrayColorspace: Bool
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParameterInputView(title: NSLocalizedString("WidthUnder", comment: ""), text: $widthThreshold, isProcessing: isProcessing)
            ParameterInputView(title: NSLocalizedString("ResizeHeight", comment: ""), text: $resizeHeight, isProcessing: isProcessing)
            ParameterInputView(title: NSLocalizedString("OutputQuality", comment: ""), text: $quality, isProcessing: isProcessing)
            ParameterInputView(title: NSLocalizedString("UnsharpRadius", comment: ""), text: $unsharpRadius, isProcessing: isProcessing)
            ParameterInputView(title: NSLocalizedString("UnsharpSigma", comment: ""), text: $unsharpSigma, isProcessing: isProcessing)
            ParameterInputView(title: NSLocalizedString("UnsharpAmount", comment: ""), text: $unsharpAmount, isProcessing: isProcessing)
            ParameterInputView(title: NSLocalizedString("UnsharpThreshold", comment: ""), text: $unsharpThreshold, isProcessing: isProcessing)

            // Thread count picker
            HStack {
                Text(NSLocalizedString("ThreadCount", comment: ""))
                    .foregroundColor(.textPrimary)
                    .frame(width: 150, alignment: .leading)
                Spacer().frame(width: 8)
                Picker("", selection: $threadCount) {
                    ForEach(1 ... 6, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 51)
                .disabled(isProcessing)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.backgroundPrimary)
                )
            }
            // Gray on off
            HStack {
                Text(NSLocalizedString("GrayColorspace", comment: ""))
                    .foregroundColor(.textPrimary)
                    .frame(width: 150, alignment: .leading)
                Spacer().frame(width: 1)
                Button(action: {
                    useGrayColorspace.toggle()
                }) {
                    Text(useGrayColorspace ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 58, height: 22)
                        .foregroundColor(useGrayColorspace ? .accent : .textPrimary)
                        .background(.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isProcessing)
            }
        }
        .padding()
        .background(.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.accent, lineWidth: 1)
        )
        .shadow(color: .accent.opacity(0.2), radius: 1, x: -2, y: 2)
        .frame(width: 240) // 设置区固定宽度，避免随窗口扩展
        .frame(maxHeight: .infinity)
    }
}

// 设置参数框样式
struct ParameterInputView: View {
    let title: String
    @Binding var text: String
    var isProcessing: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.textPrimary)
                .frame(width: 150, alignment: .leading)
            Spacer().frame(width: 0)
            TextField("", text: $text) // 使用 $text 确保绑定
                .textFieldStyle(.roundedBorder)
                .frame(width: 60) // 参数输入框
                .disabled(isProcessing) // 处理中禁用输入
                .focusable(false) // 禁用自动聚焦
        }
    }
}

// 说明区数据结构
struct ParameterInfo {
    let label: String
    let description: String
}

let parameterDescriptions: [ParameterInfo] = [
    ParameterInfo(label: NSLocalizedString("ParamDesc", comment: ""), description: ""),
    ParameterInfo(label: NSLocalizedString("UnderWidth", comment: ""), description: NSLocalizedString("UnderWidthDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("ResizeH", comment: ""), description: NSLocalizedString("ResizeHDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Quality", comment: ""), description: NSLocalizedString("QualityDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Unsharp", comment: ""), description: NSLocalizedString("UnsharpDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Radius", comment: ""), description: NSLocalizedString("RadiusDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Sigma", comment: ""), description: NSLocalizedString("SigmaDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Amount", comment: ""), description: NSLocalizedString("AmountDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Thresh", comment: ""), description: NSLocalizedString("ThreshDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Threads", comment: ""), description: NSLocalizedString("ThreadsDesc", comment: "")),
    ParameterInfo(label: NSLocalizedString("Gray", comment: ""), description: NSLocalizedString("GrayDesc", comment: ""))
]

// 说明区视图
struct ParameterDescription: View {
    let label: String
    let description: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: -50) { // 说明区中项目与描述间距调节
            Text(label)
                .font(.system(size: 13))
                .chineseItalic()
                .foregroundColor(.textSecondary)
                .frame(width: 150, alignment: .leading) // 宽度改为150，与左侧一致

            Text(description)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
        }
    }
}

// 说明文字视图
struct ParameterDescriptionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(parameterDescriptions, id: \.label) { param in
                        ParameterDescription(label: param.label, description: param.description)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding() // 括号内 .leading, 12 说明文字与左侧边距
        .background(.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.accent, lineWidth: 1) // 说明区边框颜色 #50B0FF #28D4E3
        )
        .shadow(color: .accent.opacity(0.2), radius: 1, x: 2, y: 2)
    }
}

// 处理按钮
struct ActionButtonView: View {
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(isProcessing ? "Stop" : "Go")
                    .foregroundColor(.accent) // 主文字颜色
                    .font(.system(size: 16, weight: .black))
                    .scaleEffect(1.1) // 放大1.1倍（微调视觉重量）
                Text(isProcessing ? "Stop" : "Go") // 水印效果层
                    .foregroundColor(.accent.opacity(0.3)) // 水印透明度30%
                    .font(.system(size: 18, weight: .black)) // 比主文字大2pt（增强水印感）
                    .offset(x: 1, y: 1)
                    .blendMode(.screen)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 38)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isProcessing ?
                            .backgroundSecondary :
                            .backgroundPrimary
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .shadow(
            color: .accent.opacity(0.3),
            radius: 2,
            x: 0, y: 0
        )
    }
}

// 日志使用 NSTextView 优化性能
struct DecoratedView<Content: View>: View {
    let content: Content

    var body: some View {
        ZStack {
            LogWatermarkView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 20)
                .padding(.bottom, 10)

            content
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .background(.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.accent, lineWidth: 1)
        )
        .shadow(color: .accent.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

// 日志区水印
struct LogWatermarkView: View {
    var body: some View {
        Text("Comic")
            .font(.system(size: 120, weight: .black))
            .foregroundColor(.accent.opacity(0.1))
            .rotationEffect(.degrees(-15))
            .offset(x: 50, y: 30)
            .blendMode(.screen)
            .shadow(color: .accent.opacity(0.8), radius: 6, x: 0, y: 2)
    }
}

// 说明区文字扩展 中文不斜体
extension Text {
    func chineseItalic() -> Text {
        if Locale.current.language.languageCode?.identifier == "zh" {
            return fontWeight(.medium)
        } else {
            return italic()
        }
    }
}

// 分隔线
struct GradientDividerView: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .accent.opacity(0),
                .accent.opacity(0.2),
                .accent.opacity(0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        .shadow(
            color: .accent.opacity(0.3),
            radius: 2,
            x: -2, y: 0
        )
        .blendMode(.screen)
    }
}

// 左侧面板
struct LeftPanelView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? NSLocalizedString("BuildVersionDefault", comment: "")

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Spacer()
            Image(nsImage: NSImage(named: NSImage.Name("AppIcon")) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            Text("Me2Comic")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            Text("Version \(appVersion)")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            Text(String(format: NSLocalizedString("BuildVersionLabel", comment: ""), buildVersion))
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            Spacer()
        }
        .frame(width: 200)
        .background(.leftPanelBackground)
    }
}
