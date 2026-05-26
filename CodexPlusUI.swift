import AppKit
import Foundation

struct UnlockerStatus: Decodable {
  let codexInstalled: Bool
  let codexRunning: Bool
  let unlockerRunning: Bool
  let goalsEnabled: Bool
  let debugTargetCount: Int
  let logPath: String
}

final class CodexPlusApp: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private let titleLabel = NSTextField(labelWithString: "CodexPlus")
  private let subtitleLabel = NSTextField(labelWithString: "轻量解锁器，只负责启动 Codex、开启 goals，并保持插件入口可用。")
  private let statusLabel = NSTextField(labelWithString: "正在检查状态…")
  private let detailLabel = NSTextField(labelWithString: "")
  private let startButton = NSButton(title: "启动并解锁 Codex", target: nil, action: nil)
  private let openButton = NSButton(title: "打开 Codex", target: nil, action: nil)
  private let logButton = NSButton(title: "查看日志", target: nil, action: nil)
  private let quitButton = NSButton(title: "退出", target: nil, action: nil)
  private var timer: Timer?
  private var busy = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    buildWindow()
    refreshStatus()
    timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
      self?.refreshStatus()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func buildWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 330),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.center()
    window.title = "CodexPlus"
    window.isReleasedWhenClosed = false

    let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.91, alpha: 1).cgColor
    window.contentView = contentView

    let card = NSView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.wantsLayer = true
    card.layer?.backgroundColor = NSColor.white.cgColor
    card.layer?.cornerRadius = 12
    card.layer?.borderWidth = 1
    card.layer?.borderColor = NSColor(calibratedRed: 0.84, green: 0.80, blue: 0.70, alpha: 1).cgColor
    contentView.addSubview(card)

    titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
    subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
    subtitleLabel.textColor = NSColor(calibratedWhite: 0.30, alpha: 1)
    subtitleLabel.maximumNumberOfLines = 2
    statusLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
    detailLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    detailLabel.textColor = NSColor(calibratedWhite: 0.35, alpha: 1)
    detailLabel.maximumNumberOfLines = 3

    [startButton, openButton, logButton, quitButton].forEach { button in
      button.bezelStyle = .rounded
      button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.setButtonType(.momentaryPushIn)
    }

    startButton.target = self
    startButton.action = #selector(startCodex)
    openButton.target = self
    openButton.action = #selector(openCodex)
    logButton.target = self
    logButton.action = #selector(openLog)
    quitButton.target = self
    quitButton.action = #selector(quitApp)

    startButton.contentTintColor = NSColor.white
    startButton.bezelColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)

    let stack = NSStackView(views: [
      titleLabel,
      subtitleLabel,
      statusLabel,
      detailLabel,
      startButton,
      openButton,
      logButton,
      quitButton,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    card.addSubview(stack)

    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
      card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),

      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -24),

      startButton.widthAnchor.constraint(equalToConstant: 170),
      openButton.widthAnchor.constraint(equalToConstant: 120),
      logButton.widthAnchor.constraint(equalToConstant: 120),
      quitButton.widthAnchor.constraint(equalToConstant: 90),
    ])

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func startCodex() {
    runUnlocker(arguments: ["start-service"], busyText: "正在启动后台解锁服务…") { [weak self] success, message in
      guard let self else { return }
      if success {
        self.statusLabel.stringValue = "后台服务已启动"
        self.statusLabel.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
        self.detailLabel.stringValue = "Codex 会以带调试端口的方式启动，goals 也会一并打开。"
        self.runUnlocker(arguments: ["activate-codex"], busyText: nil) { _, _ in }
      } else {
        self.statusLabel.stringValue = "启动失败"
        self.statusLabel.textColor = NSColor.systemRed
        self.detailLabel.stringValue = message
      }
      self.refreshStatus()
    }
  }

  @objc private func openCodex() {
    runUnlocker(arguments: ["activate-codex"], busyText: "正在唤起 Codex…") { [weak self] success, message in
      if !success {
        self?.statusLabel.stringValue = "无法打开 Codex"
        self?.statusLabel.textColor = NSColor.systemRed
        self?.detailLabel.stringValue = message
      }
    }
  }

  @objc private func openLog() {
    let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codexplus/unlocker.log")
    NSWorkspace.shared.open(url)
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  private func setBusy(_ newValue: Bool, text: String? = nil) {
    busy = newValue
    [startButton, openButton, logButton].forEach { $0.isEnabled = !newValue }
    if let text {
      statusLabel.stringValue = text
      statusLabel.textColor = NSColor(calibratedRed: 0.58, green: 0.38, blue: 0.12, alpha: 1)
    }
  }

  private func refreshStatus() {
    guard !busy else { return }
    runUnlocker(arguments: ["status"], busyText: nil) { [weak self] success, message in
      guard let self else { return }
      if !success {
        self.statusLabel.stringValue = "状态读取失败"
        self.statusLabel.textColor = NSColor.systemRed
        self.detailLabel.stringValue = message
        return
      }

      guard let data = message.data(using: .utf8),
            let status = try? JSONDecoder().decode(UnlockerStatus.self, from: data) else {
        self.statusLabel.stringValue = "状态解析失败"
        self.statusLabel.textColor = NSColor.systemRed
        self.detailLabel.stringValue = message
        return
      }

      if !status.codexInstalled {
        self.statusLabel.stringValue = "未检测到 Codex.app"
        self.statusLabel.textColor = NSColor.systemRed
      } else if status.codexRunning && status.unlockerRunning {
        self.statusLabel.stringValue = "Codex 正在运行，解锁服务已接管"
        self.statusLabel.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
      } else if status.codexRunning {
        self.statusLabel.stringValue = "Codex 已启动，等待解锁服务"
        self.statusLabel.textColor = NSColor(calibratedRed: 0.74, green: 0.47, blue: 0.16, alpha: 1)
      } else {
        self.statusLabel.stringValue = "Codex 未启动"
        self.statusLabel.textColor = NSColor.labelColor
      }

      self.detailLabel.stringValue = [
        "goals: \(status.goalsEnabled ? "on" : "off")",
        "unlocker: \(status.unlockerRunning ? "running" : "idle")",
        "targets: \(status.debugTargetCount)",
      ].joined(separator: "   ")
    }
  }

  private func runUnlocker(arguments: [String], busyText: String?, completion: @escaping (Bool, String) -> Void) {
    guard let scriptURL = Bundle.main.url(forResource: "unlocker", withExtension: "mjs") else {
      completion(false, "找不到 unlocker.mjs")
      return
    }

    let nodePath = "/Applications/Codex.app/Contents/Resources/node"
    let nodeURL = URL(fileURLWithPath: nodePath)
    guard FileManager.default.isExecutableFile(atPath: nodePath) else {
      completion(false, "找不到 Codex 自带 Node 运行时")
      return
    }

    if let busyText {
      setBusy(true, text: busyText)
    }

    let process = Process()
    process.executableURL = nodeURL
    process.arguments = [scriptURL.path] + arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    process.terminationHandler = { [weak self] task in
      let outData = stdout.fileHandleForReading.readDataToEndOfFile()
      let errData = stderr.fileHandleForReading.readDataToEndOfFile()
      let outText = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let text = outText.isEmpty ? errText : outText
      DispatchQueue.main.async {
        if busyText != nil {
          self?.setBusy(false)
        }
        completion(task.terminationStatus == 0, text)
      }
    }

    do {
      try process.run()
    } catch {
      if busyText != nil {
        setBusy(false)
      }
      completion(false, error.localizedDescription)
    }
  }
}

let app = NSApplication.shared
let delegate = CodexPlusApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
