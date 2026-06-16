## Purpose

确保 TokenLens 在数据处理全链路中不保存、不传输任何敏感用户数据，所有数据仅存于本地。

## Requirements

### Requirement: No Prompt or Response Storage

系统在任何情况下都不得保存用户的 prompt、response、tool output 或 thinking 原文。

#### Scenario: Usage event parsed
- **WHEN** adapter 解析 JSONL 中的 usage 事件
- **THEN** 仅提取 token 数量、model、provider、timestamp、cost 等非内容字段
- **AND** prompt、response、messages、tool output、thinking 等字段被丢弃

#### Scenario: Parse error handling
- **WHEN** JSONL 行解析失败并记录错误信息
- **THEN** 错误信息必须截断/脱敏，不得回显原始 JSONL 内容

### Requirement: No Authorization or API Key Storage

系统不得读取或保存任何形式的认证凭据。

#### Scenario: JSONL contains Authorization header or API key
- **WHEN** JSONL 行中包含 Authorization header、API key 或类似凭据
- **THEN** adapter 必须跳过这些字段，不得读取或保存

### Requirement: Dedup Key Privacy

local_usage_imports 表的去重 key 不得包含任何敏感内容。

#### Scenario: Key generated from native stable id
- **WHEN** 源数据提供原生稳定 id
- **THEN** 优先使用该 id 作为 key（通常不包含敏感内容）

#### Scenario: Key generated from usage fingerprint
- **WHEN** 源数据没有原生稳定 id，需要从 usage 属性生成 hash
- **THEN** hash 输入只能包含 timestamp、provider、model、token、cost 等非敏感字段
- **AND** 不得包含 prompt、response、tool output 的任何内容

### Requirement: Parse Context Privacy

parse_context_json 中只允许存储非敏感的元数据。

#### Scenario: Context saved across lines
- **WHEN** 解析器需要跨行保存上下文
- **THEN** parse_context_json 只允许包含 session id、cwd、provider、model 等元数据
- **AND** 不得包含任何 prompt、response、tool output、Authorization 字段

### Requirement: Data Locality

所有用户数据必须仅存储于本地，不得上传或通过网络传输。

#### Scenario: Usage data lifecycle
- **WHEN** 系统处理 usage 数据
- **THEN** 数据仅写入本地 SQLite 数据库
- **AND** 应用不向任何远程服务发送使用记录

#### Scenario: Price data is the only network request
- **WHEN** 应用需要获取模型价格
- **THEN** 仅访问 models.dev 公开 API
- **AND** 该请求不包含任何用户数据或使用记录

### Requirement: No Network Interception

当前 MVP 不实现任何形式的网络拦截。

#### Scenario: App running
- **WHEN** 应用正常运行时
- **THEN** 不做以下任何操作：
  - 不配置 HTTP/HTTPS 代理
  - 不安装 Root CA
  - 不做 HTTPS 解密
  - 不启用 Network Extension
  - 不进行透明网络捕获
