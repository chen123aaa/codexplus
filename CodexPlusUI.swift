import AppKit
import Foundation

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
}

final class CodexConfigImporterApp: NSObject, NSApplicationDelegate {
  private var window: NSWindow!

  private let titleLabel = NSTextField(labelWithString: "Codex Config Importer")
  private let subtitleLabel = NSTextField(labelWithString: "填写 Provider 和 Profile，然后直接 merge 到 ~/.codex/config.toml。")
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
  private let quitButton = NSButton(title: "退出", target: nil, action: nil)
  private let statusLabel = NSTextField(labelWithString: "填写后可先校验，再导入到 Codex。")
  private let previewTextView = NSTextView()
  private var busy = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    buildWindow()
    applyDefaultValues()
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
    window.title = "Codex Config Importer"
    window.minSize = NSSize(width: 760, height: 620)

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

    titleLabel.font = NSFont.systemFont(ofSize: 26, weight: .semibold)
    subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
    subtitleLabel.textColor = NSColor(calibratedWhite: 0.30, alpha: 1)
    subtitleLabel.maximumNumberOfLines = 2
    statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
    previewTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    previewTextView.textColor = NSColor(calibratedWhite: 0.30, alpha: 1)
    previewTextView.isEditable = false
    previewTextView.isSelectable = true
    previewTextView.drawsBackground = false

    authModeButton.font = NSFont.systemFont(ofSize: 13)
    authModeButton.addItems(withTitles: ["Desktop auth.json", "Env Key"])

    [providerIdField, providerNameField, baseUrlField, apiKeyValueField, apiKeyEnvField, profileIdField, modelField, reasoningField].forEach {
      $0.font = NSFont.systemFont(ofSize: 13)
      $0.translatesAutoresizingMaskIntoConstraints = false
    }
    headersTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

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

    [validateButton, importButton, exportButton, importJsonButton, quitButton].forEach { button in
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
    quitButton.target = self
    quitButton.action = #selector(quitApp)

    let buttonRow = NSStackView(views: [validateButton, importButton, exportButton, importJsonButton, quitButton])
    buttonRow.orientation = .horizontal
    buttonRow.spacing = 10
    buttonRow.translatesAutoresizingMaskIntoConstraints = false

    let previewScroll = NSScrollView()
    previewScroll.translatesAutoresizingMaskIntoConstraints = false
    previewScroll.borderType = .bezelBorder
    previewScroll.hasVerticalScroller = true
    previewScroll.documentView = previewTextView
    previewTextView.minSize = NSSize(width: 0, height: 150)
    previewTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    previewTextView.isVerticallyResizable = true
    previewTextView.autoresizingMask = [.width]
    previewScroll.heightAnchor.constraint(equalToConstant: 180).isActive = true

    let stack = NSStackView(views: [titleLabel, subtitleLabel, grid, buttonRow, statusLabel, previewScroll])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    card.addSubview(stack)

    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -22),
    ])

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
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

  private func applyDefaultValues() {
    providerIdField.stringValue = "openrouter"
    providerNameField.stringValue = "OpenRouter"
    baseUrlField.stringValue = "https://openrouter.ai/api/v1"
    authModeButton.selectItem(at: 0)
    apiKeyValueField.stringValue = ""
    apiKeyEnvField.stringValue = "OPENROUTER_API_KEY"
    profileIdField.stringValue = "openrouter_gpt5"
    modelField.stringValue = "gpt-5.4"
    reasoningField.stringValue = "high"
    headersTextView.string = "{\n  \"HTTP-Referer\": \"https://example.com\",\n  \"X-Title\": \"Codex Config Importer\"\n}"
  }

  @objc private func validateConfig() {
    submitConfig(command: "config-validate", busyText: "正在校验配置…")
  }

  @objc private func importConfig() {
    submitConfig(command: "config-import", busyText: "正在写入 Codex 配置…")
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
      statusLabel.stringValue = "已导出 JSON"
      statusLabel.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
    } catch {
      statusLabel.stringValue = error.localizedDescription
      statusLabel.textColor = NSColor.systemRed
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
      statusLabel.stringValue = "已从 JSON 回填表单"
      statusLabel.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)
    } catch {
      statusLabel.stringValue = error.localizedDescription
      statusLabel.textColor = NSColor.systemRed
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
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
    let headersObject: Any = headersText.isEmpty ? [:] : try JSONSerialization.jsonObject(with: Data(headersText.utf8))
    guard let headers = headersObject as? [String: String] else {
      throw NSError(domain: "CodexConfigImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "HTTP Headers 必须是 JSON 对象，且 value 都是字符串"])
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

  private func setBusy(_ newValue: Bool, text: String? = nil) {
    busy = newValue
    [validateButton, importButton, exportButton, importJsonButton].forEach { $0.isEnabled = !newValue }
    if let text {
      statusLabel.stringValue = text
      statusLabel.textColor = NSColor(calibratedRed: 0.58, green: 0.38, blue: 0.12, alpha: 1)
    }
  }

  private func submitConfig(command: String, busyText: String) {
    do {
      let payload = try currentConfigPayload()
      let data = try JSONEncoder().encode(payload)
      let encoded = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
      runCommand(arguments: [command, encoded], busyText: busyText) { [weak self] success, message in
        guard let self else { return }
        guard success,
              let data = message.data(using: .utf8),
              let response = try? JSONDecoder().decode(ConfigCommandResponse.self, from: data) else {
          self.statusLabel.stringValue = success ? "返回内容解析失败" : message
          self.statusLabel.textColor = NSColor.systemRed
          return
        }

        self.statusLabel.stringValue = command == "config-import" ? "已导入到 Codex 配置" : "配置校验通过"
        self.statusLabel.textColor = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.38, alpha: 1)

        var lines = [response.providerSnippet, "", response.profileSnippet]
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
        self.previewTextView.string = lines.joined(separator: "\n")
      }
    } catch {
      statusLabel.stringValue = error.localizedDescription
      statusLabel.textColor = NSColor.systemRed
    }
  }

  private func runCommand(arguments: [String], busyText: String?, completion: @escaping (Bool, String) -> Void) {
    guard let scriptURL = Bundle.main.url(forResource: "config-importer", withExtension: "mjs") else {
      completion(false, "找不到 config-importer.mjs")
      return
    }

    let nodePath = "/Applications/Codex.app/Contents/Resources/node"
    guard FileManager.default.isExecutableFile(atPath: nodePath) else {
      completion(false, "找不到 Codex 自带 Node 运行时")
      return
    }

    if let busyText {
      setBusy(true, text: busyText)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: nodePath)
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
      DispatchQueue.main.async {
        if busyText != nil {
          self?.setBusy(false)
        }
        completion(task.terminationStatus == 0, outText.isEmpty ? errText : outText)
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
let delegate = CodexConfigImporterApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
