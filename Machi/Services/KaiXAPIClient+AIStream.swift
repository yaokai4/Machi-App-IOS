import Foundation

// MARK: - Machi AI 流式对话 (SSE)
//
// 新增能力放在独立 extension 文件,不改共享的 KaiXAPIClient.swift。
//
// 服务端契约(与 server.py 的流式实现逐字对齐):
//   POST /api/guide/ai/chat  请求体在旧字段基础上加 {"stream": true}
//   → 200 text/event-stream,事件序列:
//       data: {"type":"delta","text":"…"}                              ×N
//       data: {"type":"done","messageId":"…","conversationId":"…",
//              "suggestions":[…],"quota":{…}}                          终止
//       data: {"type":"error","code":"…","message":"…"}                终止
//     ": ping" 心跳注释行必须忽略(顺带重置空闲超时)。
//   旧服务端兼容:
//   - 404(尚无流式支持)→ 抛 `KaiXGuideAIStreamUnsupported`,消息未被处理,
//     调用方可安全回退旧的整段 POST 重发一次。
//   - 200 但 Content-Type 非 event-stream(旧服务端忽略未知的 stream 字段、
//     消息已处理入库)→ 就地整段解码为 `.legacy` 直接使用,绝不重发
//     (重发会重复扣配额、重复入库)。

/// 服务端尚不支持流式(404)。调用方应回退旧的整段 POST(消息未被处理,可安全重发)。
struct KaiXGuideAIStreamUnsupported: Error {}

/// `done` 终止事件的载荷。字段全部可缺,新旧服务端形状都能容忍。
struct KaiXGuideAIStreamDone {
    let messageId: String?
    let conversationId: String?
    /// 追问建议(2-3 条),点按即发送。
    let suggestions: [String]
    /// 配额快照,键名与旧 `usage` 一致(membershipActive / remainingFreeUses /
    /// upgradeSuggested);服务端若换形状则全 nil,客户端沿用上一次的值。
    let quota: KaiXGuideAIUsageDTO?
}

enum KaiXGuideAIStreamEvent {
    case delta(String)
    case done(KaiXGuideAIStreamDone)
    case error(code: String, message: String)
}

enum KaiXGuideAIStreamOutcome {
    /// 流式路径:逐事件消费。`done` / `error` 后序列自动结束。
    case stream(AsyncThrowingStream<KaiXGuideAIStreamEvent, Error>)
    /// 旧服务端整段返回(已处理入库):直接当旧响应用,调用方不得重发。
    case legacy(KaiXGuideAIChatResponse)
}

extension KaiXAPIClient {
    /// SSE 解析共用解码器(JSONDecoder 配置后线程安全,避免每个事件都分配)。
    private static let aiStreamDecoder = JSONDecoder()

    /// 发送一轮 Machi AI 对话并请求流式返回。参数与 `sendGuideAIMessage` 一致。
    ///
    /// - 抛 `KaiXGuideAIStreamUnsupported`:服务端 404,调用方回退整段 POST。
    /// - 抛 `KaiXAPIError`:HTTP 层错误(配额 429 等),与旧路径同一错误形状,
    ///   调用方现有的 `handleFailure` 逻辑原样适用。
    /// - 正常返回 `.stream` 或 `.legacy`(见各 case 注释)。
    ///
    /// 走 `URLSession.shared`(与 `KaiXAPIClient.shared` 的默认会话一致);
    /// 流式 POST 不做自动重试(非幂等)。
    func streamGuideAIMessage(conversationId: String?, message: String, country: String = "jp",
                              language: String = "zh-CN", category: String? = nil,
                              ability: String? = nil, guestId: String? = nil) async throws -> KaiXGuideAIStreamOutcome {
        guard KaiXRuntimeFlags.allowBackendRequests else {
            throw URLError(.noPermissionsToReadFile)
        }
        struct Body: Encodable {
            let conversationId: String?
            let message: String
            let country: String
            let language: String
            let category: String?
            let ability: String?
            let stream: Bool
        }
        var baseString = KaiXBackend.baseURL.absoluteString
        if baseString.hasSuffix("/") { baseString = String(baseString.dropLast()) }
        guard let url = URL(string: baseString + "/api/guide/ai/chat") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 空闲超时:每个 delta / 心跳到达都会重置计时,只约束"完全没有数据"的
        // 卡死场景,不限制整体生成时长。
        req.timeoutInterval = 40
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KaiXBackend.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let guestId, !guestId.isEmpty {
            req.setValue(guestId, forHTTPHeaderField: "X-Machi-Guest-Id")
        }
        req.httpBody = try JSONEncoder().encode(Body(
            conversationId: conversationId, message: message, country: country,
            language: language, category: category, ability: ability, stream: true
        ))

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            throw KaiXGuideAIStreamUnsupported()
        }
        // 与 KaiXAPIClient.request 的 401 会话失效契约保持一致:原子清 token,
        // 只让第一个 401 触发退登流程,并回主线程投递通知。
        if http.statusCode == 401, KaiXBackend.invalidateSessionOnce() {
            await MainActor.run {
                NotificationCenter.default.post(name: .kaiXSessionInvalidated, object: nil)
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            let data = try await Self.collect(bytes, limit: 512 * 1024)
            if let api = try? Self.aiStreamDecoder.decode(KaiXAPIError.self, from: data) {
                throw api
            }
            throw KaiXAPIError(error: .init(code: "http_\(http.statusCode)", message: "HTTP \(http.statusCode)"))
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.contains("text/event-stream") else {
            // 旧服务端忽略了 "stream": true,消息已处理入库:读完整段直接返回,
            // 绝不让调用方重发(避免双倍扣配额 / 重复入库)。
            let data = try await Self.collect(bytes, limit: 4 * 1024 * 1024)
            let resp = try Self.aiStreamDecoder.decode(KaiXGuideAIChatResponse.self, from: data)
            return .legacy(resp)
        }

        // 逐行解析 SSE。契约上每个事件是一整行 `data: {json}`;为对齐 SSE 规范,
        // 单行解析失败时与后续 data 行以 "\n" 连接后重试(多行 data 事件)。
        // 注意不用「空行分帧」:URLSession.AsyncBytes.lines 会吞掉空行。
        let stream = AsyncThrowingStream<KaiXGuideAIStreamEvent, Error> { continuation in
            let task = Task {
                var pending = ""
                do {
                    for try await line in bytes.lines {
                        // ":" 开头 = 注释行(心跳 ": ping");event:/id:/retry: 等
                        // 非 data 字段一并忽略。
                        guard line.hasPrefix("data:") else { continue }
                        var payload = String(line.dropFirst(5))
                        if payload.hasPrefix(" ") { payload.removeFirst() }

                        let candidate = pending.isEmpty ? payload : pending + "\n" + payload
                        switch Self.parseStreamLine(candidate) {
                        case .event(let event):
                            pending = ""
                            continuation.yield(event)
                            if case .delta = event { continue }
                            continuation.finish()   // done / error 终止序列
                            return
                        case .ignored:
                            pending = ""            // 合法 JSON 但未知类型:前向兼容,消费掉
                        case .unparsable:
                            // 缓冲被脏行污染时,若本行可独立解析则丢弃缓冲救回。
                            if !pending.isEmpty, case .event(let event) = Self.parseStreamLine(payload) {
                                pending = ""
                                continuation.yield(event)
                                if case .delta = event { continue }
                                continuation.finish()
                                return
                            }
                            // 继续积累等待下一个 data 行;设置上限防失控增长。
                            pending = candidate.count <= 1_048_576 ? candidate : ""
                        }
                    }
                    // 服务端没发 done 就断流:正常结束序列,由调用方决定
                    // 「有部分内容按停止收尾 / 无内容按失败处理」。
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .stream(stream)
    }

    // MARK: - SSE line parsing

    private enum ParsedStreamLine {
        case event(KaiXGuideAIStreamEvent)
        /// 合法 JSON 对象但未知 type:消费掉,保持前向兼容。
        case ignored
        case unparsable
    }

    /// 单个 SSE 事件的宽容镜像。字段全可缺;suggestions 同时接受
    /// `["问题A", …]` 与 `[{"title"/"text": "问题A"}, …]` 两种形状。
    private struct RawStreamEvent: Decodable {
        let type: String?
        let text: String?
        let messageId: String?
        let conversationId: String?
        let suggestions: [TolerantSuggestion]?
        let quota: KaiXGuideAIUsageDTO?
        let code: String?
        let message: String?

        struct TolerantSuggestion: Decodable {
            let value: String?
            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer(),
                   let text = try? single.decode(String.self) {
                    value = text
                    return
                }
                struct Object: Decodable {
                    let title: String?
                    let text: String?
                }
                let object = try? Object(from: decoder)
                value = object?.title ?? object?.text
            }
        }
    }

    private static func parseStreamLine(_ json: String) -> ParsedStreamLine {
        guard let data = json.data(using: .utf8),
              let raw = try? aiStreamDecoder.decode(RawStreamEvent.self, from: data) else {
            return .unparsable
        }
        switch raw.type {
        case "delta":
            return .event(.delta(raw.text ?? ""))
        case "done":
            let suggestions = (raw.suggestions ?? [])
                .compactMap(\.value)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return .event(.done(KaiXGuideAIStreamDone(
                messageId: raw.messageId,
                conversationId: raw.conversationId,
                suggestions: suggestions,
                quota: raw.quota
            )))
        case "error":
            return .event(.error(code: raw.code ?? "ai_stream_error", message: raw.message ?? ""))
        default:
            return .ignored
        }
    }

    /// 把剩余字节读完(带上限)。非流式 / 错误响应体的兜底读取。
    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }
}
