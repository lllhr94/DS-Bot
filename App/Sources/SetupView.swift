import AgentKit
import SwiftUI

/// Connects a model service: pick one, paste its key, and the app checks it works.
struct SetupView: View {
    @ObservedObject var team: TeamModel
    /// Shown on first launch: no close button, a warmer title.
    var first = false
    var onDone: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var choice = Endpoint.presets[0]
    @State private var key = ""
    @State private var baseURL = ""
    @State private var name = ""
    @State private var modelName = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var keyFocused: Bool

    private var custom: Bool { choice.id == "custom" }

    var body: some View {
        ZStack {
            Aurora(seed: 5.2).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !first {
                        Button {
                            Haptics.light()
                            onDone()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("关闭")
                    }
                    Face(tone: 0xF5A04A, size: 72, mood: busy ? .busy : .happy, ears: .bear)
                        .padding(.top, first ? 30 : 4)
                    Text(first ? "先给团子接上大脑" : "添加模型服务")
                        .font(.system(size: 30, weight: .heavy))
                        .tracking(-0.5)
                    Text("Bot 用你自己的密钥直接连模型，对话只存在这台手机上。")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: 0x2A2A33))

                    VStack(spacing: 10) {
                        ForEach(Endpoint.presets) { preset in tile(preset) }
                    }
                    .padding(.top, 6)

                    if custom {
                        field("服务名字", "比如：Kimi", text: $name)
                        field("服务地址", "https://api.moonshot.cn/v1", text: $baseURL, keyboard: .URL)
                        field("模型名（可不填，自动获取）", "比如：kimi-k2", text: $modelName)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("密钥 API Key")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: 0x4A4A55))
                            Spacer()
                            if let help = helpURL {
                                Button("去哪拿？") { openURL(help) }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x1756CC))
                            }
                        }
                        .padding(.horizontal, 6)
                        SecureField("sk-…", text: $key)
                            .font(.system(size: 17, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($keyFocused)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xB4232F))
                            .transition(.opacity)
                    }

                    Button(action: connect) {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "正在试连" : "连接")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Color(hex: 0x1F6AE8))
                    .disabled(busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 6)
                }
                .foregroundStyle(Color(hex: 0x0B0B0F))
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 40)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: choice.id)
                .animation(.smooth, value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
    }

    private var helpURL: URL? {
        switch choice.id {
        case "deepseek": return URL(string: "https://platform.deepseek.com/api_keys")
        case "claude": return URL(string: "https://console.anthropic.com/settings/keys")
        default: return nil
        }
    }

    private func tile(_ preset: Endpoint) -> some View {
        let picked = preset.id == choice.id
        let note: String = switch preset.id {
        case "deepseek": "便宜，中文好，国内直连"
        case "claude": "最聪明，能看图；需要能连外网"
        default: "Kimi、通义、豆包、OpenRouter 等"
        }
        return Button {
            Haptics.tick(0.6)
            choice = preset
            error = nil
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).font(.system(size: 17, weight: .bold))
                    Text(note).font(.system(size: 13)).foregroundStyle(Color(hex: 0x3A3A45))
                }
                Spacer()
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(picked ? Color(hex: 0x1756CC) : Color(hex: 0x9A9AA6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.white.opacity(picked ? 0.85 : 0.45), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(picked ? Color(hex: 0x1756CC).opacity(0.5) : .white.opacity(0.8), lineWidth: picked ? 2 : 1))
            .scaleEffect(picked ? 1 : 0.98)
        }
        .buttonStyle(.plain)
    }

    private func field(_ title: String, _ hint: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x4A4A55))
                .padding(.horizontal, 6)
            TextField(hint, text: text)
                .font(.system(size: 17))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 52)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func connect() {
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var endpoint = choice
        if custom {
            let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard address.hasPrefix("http"), address.count > 10 else {
                error = "服务地址要以 https:// 开头。"
                return
            }
            endpoint.baseURL = address
            endpoint.id = "custom-\(UUID().uuidString.prefix(6))"
            let given = name.trimmingCharacters(in: .whitespacesAndNewlines)
            endpoint.name = given.isEmpty ? (URL(string: address)?.host ?? "自定义") : given
        }
        busy = true
        error = nil
        keyFocused = false
        Task {
            do {
                var models = try await endpoint.provider(key: secret).models()
                if endpoint.id == "deepseek" {
                    models = models.filter { $0.hasPrefix("deepseek") }
                } else if endpoint.kind == .anthropic {
                    models = models.filter { $0.hasPrefix("claude") }
                }
                let typed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !typed.isEmpty, !models.contains(typed) { models.insert(typed, at: 0) }
                guard !models.isEmpty else { throw TeamError(message: "连上了，但没找到能用的模型。请填上模型名再试。") }
                endpoint.models = models
                finish(endpoint, secret)
            } catch {
                // Some services do not list their models; a typed name is enough to go on.
                let typed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                if custom, !typed.isEmpty, (error as? ProviderError)?.status != 401 {
                    endpoint.models = [typed]
                    finish(endpoint, secret)
                    return
                }
                busy = false
                Haptics.lock()
                self.error = "没连上：\(error.localizedDescription)"
            }
        }
    }

    private func finish(_ endpoint: Endpoint, _ secret: String) {
        team.addEndpoint(endpoint, key: secret)
        Haptics.thud()
        busy = false
        onDone()
    }
}
