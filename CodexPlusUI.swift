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

struct ConfigPayload: Codable {
  let providerId: String
  let providerName: String
  let baseUrl: String
  let authMode: String
  let apiKeyValue: String
  let apiKeyEnv: String
  let model: String
  let profileId: String
  let modelReasoningEffort: String
  let httpHeaders: [String: String]
}

struct ConfigCommandResponse: Decodable {
  let ok: Bool
  let providerSnippet: String
  let profileSnippet: String
  let warnings: [String]
  let configPath: String?
  let backupPath: String?
  let authPath: String?
  let authBackupPath: String?
  let providerId: String?
  let profileId: String?
}

final class CodexPlusApp: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private let tabView = NSTabView()

  private let launcherTitle = NSTextField(labelWithString: "CodexPlus")
  private let launcherSubtitle = NSTextField(labelWithString: "轻量启动器，只负责启动 Codex、开启 goals，并保持插件入口可用。")
  private let launcherStatus = NSTextField(labelWithString: "正在检查状态…")
  private let launcherDetail = NSTextField(labelWithString: "")
  private let startButton = NSButton(title: "启动并解锁 Codex", target: nil, action: nil)
  private let openButton = NSButton(title: "打开 Codex", target: nil, action: nil)
  private let logButton = NSButton(title: "查看日志", target: nil, action: nil)

  private let importerTitle = NSTextField(labelWithString: "Codex Config Importer")
  private let importerSubtitle = NSTextField(labelWithString: "填完 Provider 和 Profile，直接 merge 到 ~/.codex/config.toml，不用手改 TOML。")
  private let providerIdField = NSTextField(string: "")
  private let providerNameField = NSTextField(string: "")
  private let baseUrlField = NSTextField(string: "")
  private let authModeButton = NSPopUpButton()
  private let apiKeyValueField = NSSecureTextField(string: "")
  private let apiKeyEnvField = NSTextField(string: "")
  private let profileIdField = NSTextField(string: "")
  private let modelField = NSTextField(string: "")
  private let reasoningField = NSTextField(string: "high")
  private let headersTextView = NSTextView()
  private let validateButton = NSButton(title: "校验配置", target: nil, action: nil)
  private let importButton = NSButton(title: "导入到 Codex", target: nil, action: nil)
  private let exportButton = NSButton(title: "导出 JSON", target: nil, action: nil)
  private let importJsonButton = NSButton(title: "导入 JSON", target: nil, action: nil)
  private let importerStatus = NSTextField(labelWithString: "填写后可先校验，再导入到 Codex。")
  private let importerPreviewTextView = NSTextView()

  private let quitButton = NSButton(title: "退出", target: nil, action: nil)
  private var timer: Timer?
  private var launcherBusy = false
  private var importerBusy = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    buildWindow()
    applyDefaultConfigFormValues()
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
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.center()
    window.title = "CodexPlus"
    window.minSize = NSSize(width: 760, height: 620)

    let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.91, alpha: 1).cgColor
    window.contentView = contentView

    tabView.translatesAutoresizingMaskIntoConstraints = false
    tabView.tabViewType = .topTabsBezelBorder
    contentView.addSubview(tabView)

    let launcherItem = NSTabViewItem(identifier: "launcher")
    launcherItem.label = "启动器"
    launcherItem.view = buildLauncherTab()

    let importerItem = NSTabViewItem(identifier: "importer")
    importerItem.label = "配置导入"
    importerItem.view = buildImporterTab()

    tabView.addTabViewItem(launcherItem)
    tabView.addTabViewItem(importerItem)

    NSLayoutConstraint.activate([
      tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
      tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
      tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
      tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
    ])

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func buildLauncherTab() -> NSView {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false

    let card = makeCard()
    root.addSubview(card)

    launcherTitle.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
    launcherSubtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
    launcherSubtitle.textColor = NSColor(calibratedWhite: 0.30, alpha: 1)
    launcherSubtitle.lineBreakMode = .byWordWrapping
    launcherSubtitle.maximumNumberOfLines = 2
    launcherStatus.font = NSFont.systemFont(ofSize: 15, weight: .medium)
    launcherDetail.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    launcherDetail.textColor = NSColor(calibratedWhite: 0.35, alpha: 1)

    [startButton, openButton, logButton, quitButton].forEach { button in
      button.bezelStyle = .rounded
      button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
      button.translatesAutoresizingMaskIntoConstraints = false
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

    let buttonRow = NSStackView(views: [startButton, openButton, logButton, quitButton])
    buttonRow.orientation = .horizontal
    buttonRow.spacing = 10
    buttonRow.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [
      launcherTitle,
      launcherSubtitle,
      launcherStatus,
      launcherDetail,
      buttonRow,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    card.addSubview(stack)

    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
      card.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      card.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),

      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
    ])

    return root
  }

  private func buildImporterTab() -> NSView {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false

    let card = makeCard()
    root.addSubview(card)

    importerTitle.font = NSFont.systemFont(ofSize: 26, weight: .semibold)
    importerSubtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
    importerSubtitle.textColor = NSColor(calibratedWhite: 0.30, alpha: 1)
    importerSubtitle.lineBreakMode = .byWordWrapping
    importerSubtitle.maximumNumberOfLines = 2
    importerStatus.font = NSFont.systemFont(ofSize: 14, weight: .medium)
    importerPreviewTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    importerPreviewTextView.textColor = NSColor(calibratedWhite: 0.30, alpha: 1)
    importerPreviewTextView.isEditable = false
    importerPreviewTextView.isSelectable = true
    importerPreviewTextView.drawsBackground = false

    let grid = NSGridView(views: [
      [makeLabel("Provider ID"), providerIdField],
      [makeLabel("Provider Name"), providerNameField],
      [makeLabel("Base URL"), baseUrlField],
      [makeLabel("Auth Mode"), authModeButton],
      [makeLabel("API Key"), apiKeyValueField],
      [makeLabel("API Key Env"), apiKeyEnvField],
      [makeLabel("Profile ID"), profileIdField],
      [makeLabel("Model"), modelField],
      [makeLabel("Reasoning"), reasoningField],
      [makeLabel("HTTP Headers"), makeHeadersEditor()],
    ])
    grid.translatesAutoresizingMaskIntoConstraints = false
    grid.rowSpacing = 10
    grid.columnSpacing = 14
    grid.yPlacement = .fill
    grid.xPlacement = .fill
    grid.column(at: 0).xPlacement = .trailing

    [providerIdField, providerNameField, baseUrlField, apiKeyValueField, apiKeyEnvField, profileIdField, modelField, reasoningField].forEach {
      $0.font = NSFont.systemFont(ofSize: 13)
      $0.translatesAutoresizingMaskIntoConstraints = false
    }
    headersTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    authModeButton.font = NSFont.systemFont(ofSize: 13)
    authModeButton.addItems(withTitles: ["Desktop auth.json", "Env Key"])
    authModeButton.selectItem(at: 0)

    [validateButton, importButton, exportButton, importJsonButton].forEach { button in
      button.bezelStyle = .rounded
      button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
      button.translatesAutoresizingMaskIntoConstraints = false
    }
    importButton.contentTintColor = NSColor.white
    importButton.bezelColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)

    validateButton.target = self
    validateButton.action = #selector(validateConfig)
    importButton.target = self
    importButton.action = #selector(importConfig)
    exportButton.target = self
    exportButton.action = #selector(exportJson)
    importJsonButton.target = self
    importJsonButton.action = #selector(importJson)

    let buttonRow = NSStackView(views: [validateButton, importButton, exportButton, importJsonButton])
    buttonRow.orientation = .horizontal
    buttonRow.spacing = 10
    buttonRow.translatesAutoresizingMaskIntoConstraints = false

    let previewScroll = NSScrollView()
    previewScroll.translatesAutoresizingMaskIntoConstraints = false
    previewScroll.borderType = .bezelBorder
    previewScroll.hasVerticalScroller = true
    previewScroll.documentView = importerPreviewTextView
    importerPreviewTextView.minSize = NSSize(width: 0, height: 150)
    importerPreviewTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    importerPreviewTextView.isVerticallyResizable = true
    importerPreviewTextView.autoresizingMask = [.width]
    previewScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true

    let stack = NSStackView(views: [
      importerTitle,
      importerSubtitle,
      grid,
      buttonRow,
      importerStatus,
      previewScroll,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    card.addSubview(stack)

    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
      card.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),

      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -22),
    ])

    return root
  }

  private func makeCard() -> NSView {
    let card = NSView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.wantsLayer = true
    card.layer?.backgroundColor = NSColor.white.cgColor
    card.layer?.cornerRadius = 12
    card.layer?.borderWidth = 1
    card.layer?.borderColor = NSColor(calibratedRed: 0.84, green: 0.80, blue: 0.70, alpha: 1).cgColor
    return card
  }

  private func makeLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    label.textColor = NSColor(calibratedWhite: 0.28, alpha: 1)
    return label
  }

  private func makeHeadersEditor() -> NSScrollView {
    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.borderType = .bezelBorder
    scroll.hasVerticalScroller = true
    scroll.documentView = headersTextView
    headersTextView.minSize = NSSize(width: 0, height: 90)
    headersTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    headersTextView.isVerticallyResizable = true
    headersTextView.autoresizingMask = [.width]
    scroll.heightAnchor.constraint(equalToConstant: 96).isActive = true
    scroll.widthAnchor.constraint(equalToConstant: 470).isActive = true
    return scroll
  }

  private func applyDefaultConfigFormValues() {
    providerIdField.stringValue = "openrouter"
    providerNameField.stringValue = "OpenRouter"
    baseUrlField.stringValue = "https://openrouter.ai/api/v1"
    authModeButton.selectItem(at: 0)
    apiKeyValueField.stringValue = ""
    apiKeyEnvField.stringValue = "OPENROUTER_API_KEY"
    profileIdField.stringValue = "openrouter_gpt5"
    modelField.stringValue = "gpt-5.4"
    reasoningField.stringValue = "high"
    headersTextView.string = "{\n  \"HTTP-Referer\": \"https://example.com\",\n  \"X-Title\": \"CodexPlus\"\n}"
  }

  private func scheduleAutoQuitAfterLaunch() {
    launcherStatus.stringValue = "Codex 已切到解锁模式，CodexPlus 即将自动退出"
    launcherStatus.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
    launcherDetail.stringValue = "这样可以尽量避免它继续占着前台，影响 computer-use 的权限上下文。"
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      NSApp.terminate(nil)
    }
  }

  @objc private func startCodex() {
    runCommand(arguments: ["start-service"], busyText: "正在启动后台解锁服务…", forImporter: false) { [weak self] success, message in
      guard let self else { return }
      if success {
        self.launcherStatus.stringValue = "后台服务已启动"
        self.launcherStatus.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
        self.launcherDetail.stringValue = "Codex 会以带调试端口的方式启动，goals 也会一并打开。"
        self.runCommand(arguments: ["activate-codex"], busyText: nil, forImporter: false) { _, _ in
          self.scheduleAutoQuitAfterLaunch()
        }
      } else {
        self.launcherStatus.stringValue = "启动失败"
        self.launcherStatus.textColor = NSColor.systemRed
        self.launcherDetail.stringValue = message
      }
      self.refreshStatus()
    }
  }

  @objc private func openCodex() {
    runCommand(arguments: ["activate-codex"], busyText: "正在唤起 Codex…", forImporter: false) { [weak self] success, message in
      if !success {
        self?.launcherStatus.stringValue = "无法打开 Codex"
        self?.launcherStatus.textColor = NSColor.systemRed
        self?.launcherDetail.stringValue = message
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

  @objc private func validateConfig() {
    submitConfig(command: "config-validate", busyText: "正在校验配置…")
  }

  @objc private func importConfig() {
    submitConfig(command: "config-import", busyText: "正在写入 ~/.codex/config.toml …")
  }

  @objc private func exportJson() {
    do {
      let payload = try currentConfigPayload()
      let panel = NSSavePanel()
      panel.nameFieldStringValue = "\(payload.profileId).json"
      panel.allowedContentTypes = [.json]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      let data = try JSONEncoder().encode(payload)
      try data.write(to: url)
      importerStatus.stringValue = "已导出 JSON"
      importerStatus.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
    } catch {
      importerStatus.stringValue = error.localizedDescription
      importerStatus.textColor = NSColor.systemRed
    }
  }

  @objc private func importJson() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf: url)
      let payload = try JSONDecoder().decode(ConfigPayload.self, from: data)
      applyPayloadToForm(payload)
      importerStatus.stringValue = "已从 JSON 回填表单"
      importerStatus.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
    } catch {
      importerStatus.stringValue = error.localizedDescription
      importerStatus.textColor = NSColor.systemRed
    }
  }

  private func applyPayloadToForm(_ payload: ConfigPayload) {
    providerIdField.stringValue = payload.providerId
    providerNameField.stringValue = payload.providerName
    baseUrlField.stringValue = payload.baseUrl
    authModeButton.selectItem(at: payload.authMode == "env_key" ? 1 : 0)
    apiKeyValueField.stringValue = payload.apiKeyValue
    apiKeyEnvField.stringValue = payload.apiKeyEnv
    profileIdField.stringValue = payload.profileId
    modelField.stringValue = payload.model
    reasoningField.stringValue = payload.modelReasoningEffort
    let data = try? JSONSerialization.data(withJSONObject: payload.httpHeaders, options: [.prettyPrinted, .sortedKeys])
    headersTextView.string = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }

  private func currentConfigPayload() throws -> ConfigPayload {
    let headersText = headersTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    let headersObject: Any
    if headersText.isEmpty {
      headersObject = [:]
    } else {
      headersObject = try JSONSerialization.jsonObject(with: Data(headersText.utf8))
    }
    guard let headers = headersObject as? [String: String] else {
      throw NSError(domain: "CodexPlus", code: 1, userInfo: [NSLocalizedDescriptionKey: "HTTP Headers 必须是 JSON 对象，且 value 都是字符串"])
    }
    return ConfigPayload(
      providerId: providerIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      providerName: providerNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      baseUrl: baseUrlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      authMode: authModeButton.indexOfSelectedItem == 1 ? "env_key" : "desktop_auth",
      apiKeyValue: apiKeyValueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      apiKeyEnv: apiKeyEnvField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      profileId: profileIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      modelReasoningEffort: reasoningField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
      httpHeaders: headers
    )
  }

  private func submitConfig(command: String, busyText: String) {
    do {
      let payload = try currentConfigPayload()
      let data = try JSONEncoder().encode(payload)
      let encoded = data.base64EncodedString(options: [.endLineWithLineFeed])
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
      runCommand(arguments: [command, encoded], busyText: busyText, forImporter: true) { [weak self] success, message in
        guard let self else { return }
        guard success,
              let data = message.data(using: .utf8),
              let response = try? JSONDecoder().decode(ConfigCommandResponse.self, from: data) else {
          self.importerStatus.stringValue = success ? "返回内容解析失败" : message
          self.importerStatus.textColor = NSColor.systemRed
          return
        }

        self.importerStatus.stringValue = command == "config-import"
          ? "已导入到 Codex 配置"
          : "配置校验通过"
        self.importerStatus.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)

        var lines = [
          response.providerSnippet,
          "",
          response.profileSnippet,
        ]
        if let backupPath = response.backupPath {
          lines.append("")
          lines.append("backup: \(backupPath)")
        }
        if let authPath = response.authPath {
          lines.append("auth: \(authPath)")
        }
        if let authBackupPath = response.authBackupPath {
          lines.append("auth backup: \(authBackupPath)")
        }
        if !response.warnings.isEmpty {
          lines.append("")
          lines.append(contentsOf: response.warnings.map { "note: \($0)" })
        }
        self.importerPreviewTextView.string = lines.joined(separator: "\n")
      }
    } catch {
      importerStatus.stringValue = error.localizedDescription
      importerStatus.textColor = NSColor.systemRed
    }
  }

  private func setBusy(_ busy: Bool, text: String? = nil, forImporter: Bool) {
    if forImporter {
      importerBusy = busy
      [validateButton, importButton, exportButton, importJsonButton].forEach { $0.isEnabled = !busy }
      if let text {
        importerStatus.stringValue = text
        importerStatus.textColor = NSColor(calibratedRed: 0.58, green: 0.38, blue: 0.12, alpha: 1)
      }
    } else {
      launcherBusy = busy
      [startButton, openButton, logButton].forEach { $0.isEnabled = !busy }
      if let text {
        launcherStatus.stringValue = text
        launcherStatus.textColor = NSColor(calibratedRed: 0.58, green: 0.38, blue: 0.12, alpha: 1)
      }
    }
  }

  private func refreshStatus() {
    guard !launcherBusy else { return }
    runCommand(arguments: ["status"], busyText: nil, forImporter: false) { [weak self] success, message in
      guard let self else { return }
      if !success {
        self.launcherStatus.stringValue = "状态读取失败"
        self.launcherStatus.textColor = NSColor.systemRed
        self.launcherDetail.stringValue = message
        return
      }

      guard let data = message.data(using: .utf8),
            let status = try? JSONDecoder().decode(UnlockerStatus.self, from: data) else {
        self.launcherStatus.stringValue = "状态解析失败"
        self.launcherStatus.textColor = NSColor.systemRed
        self.launcherDetail.stringValue = message
        return
      }

      if !status.codexInstalled {
        self.launcherStatus.stringValue = "未检测到 Codex.app"
        self.launcherStatus.textColor = NSColor.systemRed
      } else if status.codexRunning && status.unlockerRunning {
        self.launcherStatus.stringValue = "Codex 正在运行，解锁服务已接管"
        self.launcherStatus.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
      } else if status.codexRunning {
        self.launcherStatus.stringValue = "Codex 已启动，等待解锁服务"
        self.launcherStatus.textColor = NSColor(calibratedRed: 0.74, green: 0.47, blue: 0.16, alpha: 1)
      } else {
        self.launcherStatus.stringValue = "Codex 未启动"
        self.launcherStatus.textColor = NSColor.labelColor
      }

      self.launcherDetail.stringValue = [
        "goals: \(status.goalsEnabled ? "on" : "off")",
        "unlocker: \(status.unlockerRunning ? "running" : "idle")",
        "targets: \(status.debugTargetCount)",
      ].joined(separator: "   ")
    }
  }

  private func runCommand(arguments: [String], busyText: String?, forImporter: Bool, completion: @escaping (Bool, String) -> Void) {
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
      setBusy(true, text: busyText, forImporter: forImporter)
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
          self?.setBusy(false, forImporter: forImporter)
        }
        completion(task.terminationStatus == 0, text)
      }
    }

    do {
      try process.run()
    } catch {
      if busyText != nil {
        setBusy(false, forImporter: forImporter)
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
