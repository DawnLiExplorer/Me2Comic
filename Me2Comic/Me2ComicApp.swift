//
//  Me2ComicApp.swift
//  Me2Comic
//
//  Created by me2 on 2025/4/27.
//

import AppKit
import SwiftUI

@main
struct Me2ComicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ImageProcessorView()
        }
        .windowStyle(.hiddenTitleBar) // 隐藏标题栏
        .windowResizability(.contentMinSize) // 保持最小内容尺寸
        Settings {
            AboutView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        
        if let window = NSApp.windows.first {
            window.isMovableByWindowBackground = true // 启用全局拖拽
            window.titlebarAppearsTransparent = true // 保持标题栏透明
            window.styleMask.insert(.fullSizeContentView) // 内容扩展到标题栏区域
        }
    }
}

struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? NSLocalizedString("BuildVersionDefault", comment: "")
    @State private var selectedLanguage: String = {
        if let savedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") {
            return savedLanguage
        }

        let systemLanguage = Locale.preferredLanguages.first ?? "en"
        if systemLanguage.contains("zh-Hans") { return "zh-Hans" }
        if systemLanguage.contains("zh-Hant") { return "zh-Hant" }
        if systemLanguage.contains("ja") { return "ja" }
        return "en"
    }()
    
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSImage(named: NSImage.Name("AppIcon")) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .padding(.top, 20)
            
            Text("Me2Comic")
                .font(.title)
                .foregroundColor(.textPrimary)
            
            Text("Version \(appVersion) (Build \(buildVersion))")
                .foregroundColor(.textSecondary)
            
            Text("© 2025 Me2")
                .foregroundColor(.textSecondary)
            
            Spacer().frame(height: 20)
            
            HStack(spacing: 5) {
                Text(NSLocalizedString("Select Language", comment: ""))
                    .foregroundColor(.textPrimary)
                Picker("", selection: $selectedLanguage) {
                    Text("简体中文").tag("zh-Hans")
                    Text("繁體中文").tag("zh-Hant")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .offset(x: -5)
                .onChange(of: selectedLanguage) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "SelectedLanguage")
                    UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 290, height: 340)
        .background(.backgroundPrimary)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension ShapeStyle where Self == Color {
    /// 标题和标签
    static var textPrimary: Color { Color(hex: "#C0C1C3") }
    /// 次级文本颜色，说明区文字
    static var textSecondary: Color { Color(hex: "#A9B1C2") }
    /// 主背景颜色，按钮背景色，设置页面背景色
    static var backgroundPrimary: Color { Color(hex: "#252A33") }
    /// 次级背景颜色，用于按钮和开关
    static var backgroundSecondary: Color { Color(hex: "#35383F") }
    /// 边框修饰，分隔线
    static var accent: Color { Color(hex: "#28D4E3") }
    /// 整体背景色，右侧整体面板背景色
    static var panelBackground: Color { Color(hex: "#1F232A") }
    /// 左侧面板背景颜色，用于侧边栏
    static var leftPanelBackground: Color { Color(hex: "#1A1C22") }
}
