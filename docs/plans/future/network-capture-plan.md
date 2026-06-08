# 网络捕获功能 — 未来可能期望

> 状态：⚠️ Future / Not Implemented  
> 最后更新：2026-06-13  
> 来源：从 `docs/implementation-plan.md` 中抽离的未实现网络层能力，并结合历史 `PROJECT_SPEC.md` 设想整理。

## 1. 当前结论

TokenLens 当前 MVP 是 **local-file-first**：读取 Codex / Claude Code / pi 本地 JSONL usage，不拦截网络。

本文件记录未来可能恢复/新增的网络捕获能力。它不是当前验收范围，也不代表已承诺实现。

当前代码中不存在：

- HTTP/HTTPS Proxy server
- MITM engine
- Certificate manager
- Network Extension target
- FlowFilter
- NetworkRequestsRepository
- `network_requests` 表

## 2. 为什么暂不实现网络捕获

网络层复杂度和风险远高于本地记录扫描：

1. Network Extension 需要 entitlement、签名、系统权限与真实设备调试。
2. MITM 需要本地 Root CA、用户信任证书、TLS 兼容性处理。
3. 代理/VPN 环境容易和 Clash、Surge、Tailscale、公司 VPN、Proxyman、Charles 冲突。
4. HTTPS body 解析涉及隐私边界，必须有非常明确的默认关闭与白名单策略。
5. 当前核心价值可以先通过本地 agent 记录稳定交付。

因此当前路线：先稳定 `LocalUsageAdapter → token_usages → UI`，网络捕获作为后续高级能力。

## 3. 产品目标（若未来恢复）

未来网络捕获希望支持：

- 无需每个 CLI/IDE/SDK 单独接入，即可捕获访问主流 LLM Provider 的请求。
- 默认只记录网络元数据，不解密 HTTPS。
- 用户显式开启精确模式后，仅对 LLM Provider 白名单域名做 MITM，解析 usage。
- 网络错误必须降级，不能导致普通网络不可用。
- 所有敏感内容默认不落盘。

## 4. 分层能力

### 4.1 本地 HTTP/HTTPS 代理（手动模式）

可能能力：

- 监听 `127.0.0.1:8899`。
- 支持 HTTP request 与 HTTPS `CONNECT` tunnel。
- 用户手动设置 `HTTP_PROXY` / `HTTPS_PROXY`。
- 不启用 MITM 时只记录 host、port、bytes、latency、status/error。
- 不读取 HTTPS body。

验收设想：

- `curl` 通过代理访问 LLM Provider 成功。
- 普通代理失败不能导致 App 崩溃。
- 可将网络元数据写入未来 `network_requests`。

### 4.2 FlowFilter / Provider 白名单

可能能力：

- 只捕获 Provider 白名单域名，例如：
  - `api.openai.com`
  - `api.anthropic.com`
  - `openrouter.ai`
  - `api.deepseek.com`
  - `generativelanguage.googleapis.com`
  - `api.mistral.ai`
  - `api.groq.com`
  - `api.x.ai`
- 非白名单域名直接放行。
- MVP 不允许关闭“只捕获 provider whitelist”安全限制。

### 4.3 MITM 精确模式

可能能力：

- 生成本地 Root CA。
- 指引用户手动信任 CA。
- 仅对白名单 Provider 域名动态签发 leaf cert 并解密。
- 解析 request/response/SSE usage。
- 将解析出的 token usage 写入 `token_usages`（或未来专门网络 usage 表）。
- 默认不保存 prompt/response/Authorization/API key。

验收设想：

- 用户信任 CA 后，可解析 OpenAI 非 streaming usage。
- 可解析 streaming SSE 中的最终 usage。
- 非白名单域名不解密。
- Authorization header 不落盘。

### 4.4 Network Extension 透明捕获

可能能力：

- 使用 `NETransparentProxyProvider`。
- 用户无需设置 `HTTP_PROXY`。
- 只捕获 LLM Provider 白名单流量。
- 将 flow 转给 Local Proxy Core。
- 普通网站访问不受影响。
- 监控开关立即生效。

明确避免：

- 不优先使用 `NEPacketTunnelProvider`。
- 不做全局 VPN。
- 不接管 DNS。
- 不主动修改用户现有 VPN/代理配置。

### 4.5 Upstream Proxy / 冲突检测

可能能力：

- 检测系统 HTTP/HTTPS proxy。
- 检测活跃 VPN / Network Extension。
- 检测常见工具：Clash、Surge、Tailscale、Proxyman、Charles 等。
- 支持 upstream proxy 转发，兼容公司代理或本地代理链。

UI 提示设想：

```text
TokenLens is running in compatibility mode.
Some traffic may not be captured because another VPN/proxy is active.
```

## 5. 可能 Schema（未来再评估）

若恢复网络捕获，可新增 `network_requests`：

```sql
CREATE TABLE IF NOT EXISTS network_requests (
  id TEXT PRIMARY KEY,
  provider_id TEXT,
  host TEXT NOT NULL,
  port INTEGER,
  method TEXT,
  path TEXT,
  status_code INTEGER,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  latency_ms INTEGER,
  request_bytes INTEGER DEFAULT 0,
  response_bytes INTEGER DEFAULT 0,
  decrypted INTEGER NOT NULL DEFAULT 0,
  process_name TEXT,
  bundle_id TEXT,
  error_code TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL
);
```

网络解析出的 token 用量应优先复用当前 `token_usages` 模型，可能需要增加来源字段或独立 occurrence metadata。具体 schema 需在实现前重新设计，不应直接复活历史 `model_calls`。

## 6. 未来实现顺序建议

| Phase | 能力 | 说明 |
|---|---|---|
| N1 | Local Proxy Core | 手动 HTTP_PROXY 模式；只记录网络元数据 |
| N2 | FlowFilter + `network_requests` | Provider 域名白名单与网络请求账本 |
| N3 | CertificateManager | Root CA 生成、信任/删除指引 |
| N4 | MITM Engine | 仅白名单域名解密；解析 JSON/SSE usage |
| N5 | Network Extension | NETransparentProxyProvider 透明捕获 |
| N6 | Upstream Proxy + Conflict UI | 兼容代理/VPN 环境 |
| N7 | 分发 | Developer ID、notarized DMG、权限/证书引导 |

每个 Phase 都必须独立可运行、可回滚、带测试。

## 7. 隐私与安全约束

未来实现必须保持：

1. 默认不启用 MITM。
2. 默认不保存 prompt/response。
3. 默认不保存 Authorization/API key。
4. 只对白名单 Provider 域名解密。
5. App 提供一键暂停网络捕获。
6. App 崩溃/退出不得导致系统断网。
7. 网络错误必须降级为“未捕获/估算”，不能阻断普通访问。
8. 开发者模式以外不得保存明文请求/响应。

## 8. 历史实现线索

以下曾在历史实现/计划中出现，但当前代码已移除。若恢复需从 git 历史或重新实现：

- `Sources/TokenLensNetworkExtension/TransparentProxyProvider.swift`
- `Sources/TokenLensCore/FlowFilter.swift`
- `Sources/TokenLensApp/Core/Proxy/ProxyServer.swift`
- `Sources/TokenLensApp/Core/Proxy/MITMEngine.swift`
- `Sources/TokenLensApp/Core/Proxy/UpstreamProxyConfig.swift`
- `Sources/TokenLensApp/Core/Certificate/CertificateManager.swift`
- `Sources/TokenLensApp/Database/NetworkRequestsRepository.swift`
- `Tests/TokenLensTests/ProxyTests.swift`
- `Tests/TokenLensTests/CertificateManagerTests.swift`
- `Tests/TokenLensTests/UpstreamProxyConfigTests.swift`

## 9. 触发恢复的前置条件

建议同时满足后再启动网络层：

- 本地扫描 MVP 稳定运行。
- `token_usages`、定价、UI、隐私测试长期稳定。
- 明确是否真的需要网络捕获来覆盖 local logs 无法覆盖的场景。
- 有 Developer ID / entitlement / Network Extension 调试环境。
- 先完成详细 ADR，尤其是隐私、失败降级、卸载路径。