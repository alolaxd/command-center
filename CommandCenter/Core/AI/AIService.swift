import Foundation
import Observation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic = "Anthropic (Claude)", openai = "OpenAI", ollama = "Ollama (local)", openrouter = "OpenRouter"
    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-4.1-mini"
        case .ollama: "llama3.2"
        case .openrouter: "openrouter/auto"
        }
    }
    var keychainKey: String? {
        switch self {
        case .anthropic: KeychainKey.anthropic
        case .openai: KeychainKey.openai
        case .openrouter: KeychainKey.openrouter
        case .ollama: nil
        }
    }
}

struct AIMessage: Codable, Hashable {
    enum Role: String, Codable { case user, assistant }
    var role: Role
    var content: String
}

enum AIError: LocalizedError {
    case notConfigured(String), http(Int, String), refusal(String), badResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured(let s): s
        case .http(let code, let body): "HTTP \(code): \(body.prefix(300))"
        case .refusal(let s): "The model declined this request\(s.isEmpty ? "" : ": \(s)")."
        case .badResponse: "Unexpected response from AI provider."
        }
    }
}

/// Provider-agnostic AI access used by journal summaries, RSS digests, NL commands, triage and "ask my data".
@MainActor @Observable
final class AIService {
    static let shared = AIService()

    private(set) var activeJobs = 0
    private(set) var ollamaDetected = false

    var provider: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.string(forKey: SettingsKey.aiProvider) ?? "") ?? .anthropic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKey.aiProvider) }
    }

    func model(for p: AIProvider) -> String {
        let m = UserDefaults.standard.string(forKey: SettingsKey.aiModel(p)) ?? ""
        return m.isEmpty ? p.defaultModel : m
    }

    var ollamaURL: URL {
        URL(string: UserDefaults.standard.string(forKey: SettingsKey.ollamaURL) ?? "") ?? URL(string: "http://localhost:11434")!
    }

    var isConfigured: Bool {
        if provider == .ollama { return ollamaDetected }
        return provider.keychainKey.flatMap(Keychain.get) != nil
    }

    /// Auto-detects a running Ollama and selects it if no cloud provider has a key.
    func detectOllama() async {
        var req = URLRequest(url: ollamaURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 1.5
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { ollamaDetected = false; return }
        ollamaDetected = true
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = obj["models"] as? [[String: Any]], let first = models.first?["name"] as? String,
           (UserDefaults.standard.string(forKey: SettingsKey.aiModel(.ollama)) ?? "").isEmpty {
            UserDefaults.standard.set(first, forKey: SettingsKey.aiModel(.ollama))
        }
        if UserDefaults.standard.string(forKey: SettingsKey.aiProvider) == nil,
           AIProvider.allCases.allSatisfy({ $0.keychainKey.flatMap(Keychain.get) == nil }) {
            provider = .ollama
        }
    }

    /// Single-shot completion.
    func complete(system: String? = nil, _ messages: [AIMessage], effort: String? = nil) async throws -> String {
        var out = ""
        for try await chunk in stream(system: system, messages, effort: effort) { out += chunk }
        return out
    }

    func ask(_ prompt: String, system: String? = nil) async throws -> String {
        try await complete(system: system, [AIMessage(role: .user, content: prompt)])
    }

    /// Streams text deltas from the configured provider.
    func stream(system: String? = nil, _ messages: [AIMessage], effort: String? = nil) -> AsyncThrowingStream<String, Error> {
        let provider = self.provider
        let model = self.model(for: provider)
        let key = provider.keychainKey.flatMap(Keychain.get)
        let ollama = ollamaURL
        return AsyncThrowingStream { continuation in
            let task = Task {
                await MainActor.run { self.activeJobs += 1 }
                defer { Task { @MainActor in self.activeJobs -= 1 } }
                do {
                    if provider != .ollama && key == nil {
                        throw AIError.notConfigured("Add an API key for \(provider.rawValue) in Settings → AI.")
                    }
                    let request = try Self.buildRequest(provider: provider, model: model, key: key, ollama: ollama,
                                                        system: system, messages: messages, effort: effort)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 2000 { break } }
                        throw AIError.http(status, body)
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let text = try Self.parse(line: line, provider: provider) { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Wire formats

    nonisolated static func buildRequest(provider: AIProvider, model: String, key: String?, ollama: URL,
                                                 system: String?, messages: [AIMessage], effort: String?) throws -> URLRequest {
        var req: URLRequest
        var body: [String: Any]
        let msgs = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        switch provider {
        case .anthropic:
            // Raw HTTP: there is no official Anthropic SDK for Swift.
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            // Server-side refusal fallback: if the model declines, the API reroutes to a suitable model.
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body = ["model": model, "max_tokens": 64000, "stream": true, "messages": msgs,
                    "thinking": ["type": "adaptive"], "fallbacks": "default"]
            if let effort { body["output_config"] = ["effort": effort] }
            if let system { body["system"] = system }
        case .openai, .openrouter:
            let base = provider == .openai ? "https://api.openai.com/v1" : "https://openrouter.ai/api/v1"
            req = URLRequest(url: URL(string: base + "/chat/completions")!)
            req.setValue("Bearer \(key ?? "")", forHTTPHeaderField: "Authorization")
            var all = msgs
            if let system { all.insert(["role": "system", "content": system], at: 0) }
            body = ["model": model, "stream": true, "messages": all]
        case .ollama:
            req = URLRequest(url: ollama.appendingPathComponent("api/chat"))
            var all = msgs
            if let system { all.insert(["role": "system", "content": system], at: 0) }
            body = ["model": model, "stream": true, "messages": all]
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    nonisolated static func parse(line: String, provider: AIProvider) throws -> String? {
        switch provider {
        case .ollama:
            guard let obj = json(line) else { return nil }
            return (obj["message"] as? [String: Any])?["content"] as? String
        case .openai, .openrouter:
            guard line.hasPrefix("data: "), let obj = json(String(line.dropFirst(6))) else { return nil }
            let choice = (obj["choices"] as? [[String: Any]])?.first
            return (choice?["delta"] as? [String: Any])?["content"] as? String
        case .anthropic:
            guard line.hasPrefix("data: "), let obj = json(String(line.dropFirst(6))) else { return nil }
            switch obj["type"] as? String {
            case "content_block_delta":
                let delta = obj["delta"] as? [String: Any]
                return delta?["type"] as? String == "text_delta" ? delta?["text"] as? String : nil
            case "message_delta":
                let delta = obj["delta"] as? [String: Any]
                if delta?["stop_reason"] as? String == "refusal" {
                    let details = delta?["stop_details"] as? [String: Any]
                    throw AIError.refusal(details?["explanation"] as? String ?? "")
                }
                return nil
            case "error":
                let err = obj["error"] as? [String: Any]
                throw AIError.http(0, err?["message"] as? String ?? "stream error")
            default: return nil
            }
        }
    }

    nonisolated private static func json(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
