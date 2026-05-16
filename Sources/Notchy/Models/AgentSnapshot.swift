struct AgentSnapshot {
    let kind: AgentKind
    let name: String
    let status: String
    let project: String
    let lastEventTs: Int
    let usage: AgentUsageModel?
}
