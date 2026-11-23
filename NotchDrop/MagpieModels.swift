//
//  MagpieModels.swift
//  NotchEvery
//
//  Magpie 文件解码与聚合的模型类型。
//

import Foundation

/// usage.jsonl 单行解码后的用量记录（已过滤内部探活行）。
public struct MagpieUsageRecord: Equatable {
    public let id: String            // rid ?? "<route_id>-<byteOffset>"
    public let routeID: Int64?
    public let time: Date
    public let agent: String
    public let provider: String
    public let providerAccount: String
    public let model: String
    public let served: String?
    public let req: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let reasoning: Int
    public let durationMs: Int?
    public let ttftMs: Int?
    public let maskingMs: Int?
    public let status: Int?
    public let handedOn: Bool

    public init(
        id: String,
        routeID: Int64?,
        time: Date,
        agent: String,
        provider: String,
        providerAccount: String,
        model: String,
        served: String?,
        req: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheRead: Int,
        cacheWrite: Int,
        reasoning: Int,
        durationMs: Int?,
        ttftMs: Int?,
        maskingMs: Int?,
        status: Int?,
        handedOn: Bool
    ) {
        self.id = id
        self.routeID = routeID
        self.time = time
        self.agent = agent
        self.provider = provider
        self.providerAccount = providerAccount
        self.model = model
        self.served = served
        self.req = req
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
        self.durationMs = durationMs
        self.ttftMs = ttftMs
        self.maskingMs = maskingMs
        self.status = status
        self.handedOn = handedOn
    }
}
