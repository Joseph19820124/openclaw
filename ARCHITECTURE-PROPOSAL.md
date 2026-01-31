# OpenClaw Gateway + Node 架构方案 (已部署)

## 概述

在 AWS us-east-1 区域部署 OpenClaw 分布式架构，包含一台 Gateway 服务器和一台 Node 服务器。

**部署状态：✅ 已完成**

## 架构图

```
                         Internet
                            │
                            ▼
                    ┌───────────────┐
                    │  Elastic IP   │
                    │ 44.217.250.149│
                    └───────┬───────┘
                            │
    ┌───────────────────────┼─────────────────────────────┐
    │                 AWS us-east-1                        │
    │                                                      │
    │  ┌─────────────────┐        ┌─────────────────┐    │
    │  │   openclaw-gw   │        │  openclaw-node  │    │
    │  │   (t3.medium)   │        │   (t3.small)    │    │
    │  │                 │        │                 │    │
    │  │ ┌─────────────┐ │        │ ┌─────────────┐ │    │
    │  │ │  Gateway    │ │◄──WS───│ │    Node     │ │    │
    │  │ │  :18789     │ │        │ │  (Client)   │ │    │
    │  │ └─────────────┘ │        │ └─────────────┘ │    │
    │  │                 │        │                 │    │
    │  │ 44.217.250.149  │        │  54.82.26.182   │    │
    │  │ 172.31.31.188   │        │  172.31.17.79   │    │
    │  └─────────────────┘        └─────────────────┘    │
    │                                                      │
    └──────────────────────────────────────────────────────┘
```

## 已部署资源

### EC2 实例

| 名称 | Instance ID | 类型 | 公网 IP | 私网 IP | EBS |
|------|-------------|------|---------|---------|-----|
| openclaw-gw | i-0b1fb112ce9b04e68 | t3.medium | 44.217.250.149 (EIP) | 172.31.31.188 | 100GB gp3 |
| openclaw-node | i-0ebcf0b7de510581d | t3.small | 54.82.26.182 | 172.31.17.79 | 100GB gp3 |

### 网络配置

| 资源 | ID/值 |
|------|-------|
| Security Group | sg-0f4ea68c96f52aa6a (openclaw-sg) |
| Elastic IP | eipalloc-0400e00ce0466d5c9 → 44.217.250.149 |
| 开放端口 | 22 (SSH), 443, 18789 (Gateway WebSocket) |

### SSH Key

| 项目 | 值 |
|------|-----|
| Key Name | openclaw-key |
| 本地路径 | ~/.ssh/openclaw-key.pem |

### IAM

| 资源 | 名称 |
|------|------|
| IAM Role | openclaw-ec2-role |
| Instance Profile | openclaw-ec2-profile |
| 附加策略 | CloudWatchAgentServerPolicy, AmazonSSMManagedInstanceCore |

## 重要：Gateway vs Node 启动方式

### ⚠️ 关键区别

**Gateway 服务器 (openclaw-gw)** 运行 `gateway run`：
```bash
openclaw gateway run --bind lan --port 18789 --force --allow-unconfigured
```

**Node 服务器 (openclaw-node)** 运行 `node run`（不是 gateway！）：
```bash
openclaw node run
```

### 错误示例 ❌

```bash
# 错误！Node 不应该运行 gateway
openclaw gateway run --bind lan --port 18789
```

### 正确示例 ✅

```bash
# Gateway 服务器
openclaw gateway run --bind lan --port 18789

# Node 服务器 - 连接到 Gateway
openclaw node run
```

## systemd 服务配置

### Gateway 服务 (/etc/systemd/system/openclaw-gateway.service)

```ini
[Unit]
Description=OpenClaw Gateway Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/openclaw
Environment=NODE_ENV=production
Environment=PATH=/home/ec2-user/.nvm/versions/node/v22.22.0/bin:/usr/bin:/bin
ExecStart=/home/ec2-user/openclaw/openclaw.mjs gateway run --bind lan --port 18789 --force --allow-unconfigured
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Node 服务 (/etc/systemd/system/openclaw-node.service)

```ini
[Unit]
Description=OpenClaw Node Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/openclaw
Environment=NODE_ENV=production
Environment=PATH=/home/ec2-user/.nvm/versions/node/v22.22.0/bin:/usr/bin:/bin
ExecStart=/home/ec2-user/openclaw/openclaw.mjs node run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Node 连接 Gateway 配置

### Node 配置文件 (~/.openclaw/openclaw.json)

```json
{
  "gateway": {
    "mode": "remote",
    "remote": {
      "url": "ws://44.217.250.149:18789",
      "token": "<GATEWAY_TOKEN>"
    }
  }
}
```

设置命令：
```bash
openclaw config set gateway.mode remote
openclaw config set gateway.remote.url ws://44.217.250.149:18789
openclaw config set gateway.remote.token <GATEWAY_TOKEN>
```

### Gateway 配置文件 (~/.openclaw/openclaw.json)

```json
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "auth": {
      "token": "<GATEWAY_TOKEN>"
    }
  }
}
```

## Node 配对流程

1. Node 启动后自动尝试连接 Gateway
2. Gateway 收到配对请求，显示在 pending 列表
3. 在 Gateway 上批准配对：

```bash
# 查看待批准的配对请求
openclaw devices list

# 批准配对
openclaw devices approve <request-id>

# 验证连接状态
openclaw nodes status
```

## Gateway 向 Node 发送命令

### 查看 Node 状态

```bash
openclaw nodes status
```

输出示例：
```
Known: 1 · Paired: 1 · Connected: 1
┌──────────────────┬────────────────┬───────────────────────┐
│ Node             │ IP             │ Status                │
├──────────────────┼────────────────┼───────────────────────┤
│ ip-172-31-17-79  │ 54.82.26.182   │ paired · connected    │
└──────────────────┴────────────────┴───────────────────────┘
```

### 执行远程命令

```bash
# 获取 CPU 负载
openclaw nodes invoke --node 54.82.26.182 \
  --command system.run \
  --params '{"command":["cat","/proc/loadavg"]}'

# 获取内存使用
openclaw nodes invoke --node 54.82.26.182 \
  --command system.run \
  --params '{"command":["free","-h"]}'

# 获取磁盘使用
openclaw nodes invoke --node 54.82.26.182 \
  --command system.run \
  --params '{"command":["df","-h","/"]}'

# 获取系统运行时间
openclaw nodes invoke --node 54.82.26.182 \
  --command system.run \
  --params '{"command":["uptime"]}'
```

### Node 支持的命令

| 命令 | 说明 |
|------|------|
| `system.run` | 执行 shell 命令 |
| `system.which` | 查找命令路径 |
| `system.execApprovals.get` | 获取执行权限配置 |
| `system.execApprovals.set` | 设置执行权限配置 |
| `browser.proxy` | 浏览器代理 |

## Node 命令执行权限

配置文件：`~/.openclaw/exec-approvals.json`

当前配置（测试环境 - 允许所有命令）：
```json
{
  "version": 1,
  "socket": {
    "path": "/home/ec2-user/.openclaw/exec-approvals.sock",
    "token": "PDZdiZJ9LTMyBMoY73F7II-KLCNqrZ_I"
  },
  "defaults": {
    "security": "full"
  },
  "agents": {}
}
```

### 安全级别

| 级别 | 说明 |
|------|------|
| `"full"` | 允许执行任意命令（当前配置） |
| `"allowlist"` | 仅允许白名单中的命令 |
| `"deny"` | 拒绝所有远程命令 |

## CloudWatch 监控

### 告警列表

| 告警名称 | 指标 | 阈值 |
|---------|------|------|
| OpenClaw-GW-CPU-High | CPUUtilization | > 80% |
| OpenClaw-GW-Memory-High | mem_used_percent | > 85% |
| OpenClaw-GW-StatusCheck | StatusCheckFailed | >= 1 |
| OpenClaw-Node-CPU-High | CPUUtilization | > 80% |
| OpenClaw-Node-StatusCheck | StatusCheckFailed | >= 1 |

### CloudWatch Agent 配置

两台机器均已安装 CloudWatch Agent，收集：
- CPU 使用率
- 内存使用率
- 磁盘使用率
- 系统日志

## SSH 连接

```bash
# 连接 Gateway
ssh -i ~/.ssh/openclaw-key.pem ec2-user@44.217.250.149

# 连接 Node
ssh -i ~/.ssh/openclaw-key.pem ec2-user@54.82.26.182
```

## 服务管理

```bash
# Gateway
sudo systemctl status openclaw-gateway
sudo systemctl restart openclaw-gateway
journalctl -u openclaw-gateway -f

# Node
sudo systemctl status openclaw-node
sudo systemctl restart openclaw-node
journalctl -u openclaw-node -f
```

## 成本估算 (us-east-1)

| 资源 | 月费用 |
|------|--------|
| t3.medium (on-demand) | ~$30 |
| t3.small (on-demand) | ~$15 |
| EBS (100GB gp3 x2) | ~$16 |
| Elastic IP | ~$3.6 |
| CloudWatch | ~$2.5 |
| **总计** | **~$67/月** |

## 模拟 IM 工具

由于测试环境不便使用 Slack/Telegram 等即时通讯工具，我们创建了一个模拟 IM 工具。

### 启动方式

```bash
ssh -i ~/.ssh/openclaw-key.pem ec2-user@44.217.250.149
cd ~/openclaw
./tools/sim-im.sh
```

### 快捷命令

| 命令 | 功能 |
|------|------|
| `cpu` | 查询 Node CPU 负载 |
| `mem` | 查询 Node 内存使用 |
| `disk` | 查询 Node 磁盘使用 |
| `status` | 查询整体状态 |
| `nodes` | 列出所有 Node |
| `top` | 查看进程列表 |
| `help` | 显示帮助 |
| `exit` | 退出 |

### 自然语言查询

输入任意问题，AI 会自动处理：
- "请帮我查看一下Node节点的CPU使用情况"
- "检查服务器内存还剩多少"
- "磁盘快满了吗？"

### 工作原理

```
用户输入 → sim-im.sh → OpenClaw Agent → Z.AI GLM-4.6 → nodes invoke → Node 执行命令 → 返回结果
```

## LLM 配置

### 模型提供商

| 项目 | 值 |
|------|-----|
| Provider | Z.AI (智谱 AI) |
| Model | zai/glm-4.6 |
| API Endpoint | https://open.bigmodel.cn |

### 配置方式

Gateway systemd 服务中配置环境变量：
```ini
Environment=ZAI_API_KEY=<your-api-key>
```

或在 shell 中导出：
```bash
export ZAI_API_KEY=<your-api-key>
```

### 设置默认模型

```bash
openclaw models set zai/glm-4.6
```

## 注意事项

1. **这是测试环境**，与生产环境物理隔离
2. Node 命令执行权限设置为 `full`，生产环境应使用 `allowlist`
3. 当前使用 HTTP/WS（端口 18789），未启用 TLS
4. Gateway Token 已配置，Node 连接需要提供正确的 token
5. Z.AI API Key 已配置在 Gateway systemd 服务中

## 故障排除

### Node 无法连接 Gateway

1. 检查 Security Group 是否开放 18789 端口
2. 检查 Node 配置的 `gateway.remote.url` 和 `gateway.remote.token`
3. 查看 Node 日志：`journalctl -u openclaw-node -f`

### 配对请求未出现

1. 确认 Node 使用 `node run` 而不是 `gateway run`
2. 检查 Gateway 日志中是否有连接记录
3. 重启 Node 服务：`sudo systemctl restart openclaw-node`

### 命令执行被拒绝

1. 检查 Node 的 `~/.openclaw/exec-approvals.json`
2. 确认 `defaults.security` 不是 `deny`
3. 重启 Node 服务使配置生效

## AI Agent Architecture (Gateway vs Node Responsibilities)

### Core Concept

- **Gateway** = The Brain (runs AI Agent + calls LLM)
- **Node** = The Hands (only executes commands, no AI logic)
- **LLM** = Only called on Gateway side, Node has zero AI capability

### Gateway Can Query Paired Nodes

```bash
# On Gateway, check all paired nodes
openclaw nodes status

# Output:
# Known: 1 · Paired: 1 · Connected: 1
```

Node pairing data is stored at `~/.openclaw/nodes/paired.json`.

### Node Registration Model

- A Node can only connect to **ONE Gateway at a time**
- Node config stores single gateway: `gateway.remote.url`
- To switch Gateway: change config and re-pair (no explicit "unregister" needed)
- Old Gateway will see the Node as "disconnected" (pairing record remains)

### Complete Request Flow Diagram

```
+-----------------------------------------------------------------------------+
|                         COMPLETE REQUEST FLOW                               |
+-----------------------------------------------------------------------------+

+----------+     +----------------------------------------------------------+
| Telegram |     |                      Gateway (GW)                        |
|   User   |     |                                                          |
+----+-----+     |  +-----------+    +------------+    +--------------+     |
     |           |  | Telegram  |    |  AI Agent  |    |  nodes-tool  |     |
     |           |  |   Bot     |--->| (Pi Agent) |--->|              |     |
     | "Query    |  +-----------+    +-----+------+    +------+-------+     |
     |  CPU"     |                         |                  |             |
     +-----------+-------------------------+                  |             |
     |           |                         |                  |             |
     |           |                         v                  |             |
     |           |               +-----------------+          |             |
     |           |               |    Z.AI LLM     |          |             |
     |           |               |   (GLM-4.6)     |          |             |
     |           |               +--------+--------+          |             |
     |           |                        |                   |             |
     |           |  "I need to call       |                   |             |
     |           |   nodes tool"          v                   |             |
     |           |               +-----------------+          |             |
     |           |               | Tool Execution  |<---------+             |
     |           |               |  node.invoke    |                        |
     |           |               +--------+--------+                        |
     |           |                        |                                 |
     +-----------+------------------------+----------------------------------+
                 |                        |
                 |                        | WebSocket (port 18789)
                 |                        v
                 |          +----------------------------------+
                 |          |             Node                 |
                 |          |                                  |
                 |          |  Received: system.run            |
                 |          |  params: ["cat","/proc/loadavg"] |
                 |          |                                  |
                 |          |  +---------------------------+   |
                 |          |  | Execute: cat /proc/loadavg|   |
                 |          |  | Result: 0.15 0.10 0.05... |   |
                 |          |  +---------------------------+   |
                 |          |                                  |
                 |          +----------------+-----------------+
                 |                           |
                 |                           | Return result
                 |                           v
                 |          +-------------------------------------+
                 |          |           Gateway (GW)              |
                 |          |                                     |
                 |          |  AI Agent receives tool result      |
                 |          |  |                                  |
                 |          |  v                                  |
                 |          |  Call LLM to generate final reply   |
                 |          |  |                                  |
                 |          |  v                                  |
                 |          |  "Node CPU load: 0.15, 0.10, 0.05"  |
                 |          +-------------------------------------+
                 |                           |
                 |                           | Send reply
                 v                           v
          +----------+              +--------------+
          | Telegram |<-------------|  Bot Reply   |
          |   User   |              |              |
          +----------+              +--------------+
```

### Simplified Flow

```
User (Telegram/Slack/etc.)
    | "Query Node CPU usage"
    v
Gateway (receives message)
    |
    v
AI Agent (analyzes user intent)
    |
    v
LLM (Z.AI GLM-4.6)
    | Decides to call nodes tool
    v
Tool: nodes (action=run, command=["cat", "/proc/loadavg"])
    | WebSocket
    v
Node (executes command)
    | Returns: "0.15 0.10 0.05 1/234 12345"
    v
Gateway (receives result)
    |
    v
LLM (generates natural language reply)
    | "Node CPU load: 1min=0.15, 5min=0.10, 15min=0.05"
    v
Gateway (sends reply)
    |
    v
User (Telegram) receives reply
```

### Key Source Code Locations

| Step | Source File | Description |
|------|-------------|-------------|
| 1. Message entry | `src/telegram/bot-message.ts` | Receives Telegram message |
| 2. Message dispatch | `src/telegram/bot-message-dispatch.ts` | Dispatches to AI Agent |
| 3. AI Agent run | `src/auto-reply/reply/agent-runner.ts` | Runs Pi Agent (AI) |
| 4. Call LLM | `src/agents/pi-embedded-runner.ts` | Calls Z.AI GLM-4.6 |
| 5. Nodes tool | `src/agents/tools/nodes-tool.ts` | Provides `nodes` tool to LLM |
| 6. Send to Node | `callGatewayTool("node.invoke", ...)` | Sends via WebSocket |
| 7. Node executes | `src/node-host/runner.ts` | Executes `system.run` |

### nodes-tool.ts - The "run" Action

```typescript
// src/agents/tools/nodes-tool.ts:388-441
case "run": {
  const node = readStringParam(params, "node", { required: true });
  const nodeId = resolveNodeIdFromList(nodes, node);

  // Send invoke request to Node via Gateway
  const raw = await callGatewayTool("node.invoke", gatewayOpts, {
    nodeId,
    command: "system.run",           // Command type for Node
    params: {
      command,                        // e.g.: ["cat", "/proc/loadavg"]
      cwd,
      env,
      timeoutMs: commandTimeoutMs,
    },
  });

  return jsonResult(raw?.payload ?? {});
}
```

### Why This Architecture?

| Component | Responsibility | Has LLM? | Has AI Logic? |
|-----------|----------------|----------|---------------|
| **Gateway** | Central hub, runs AI Agent, calls LLM, routes messages | Yes | Yes |
| **Node** | Execution endpoint, runs commands, returns results | No | No |

This separation allows:
1. **Centralized AI**: Only Gateway needs LLM API keys
2. **Scalability**: Many Nodes can connect to one Gateway
3. **Security**: Node only executes pre-approved commands
4. **Simplicity**: Node is lightweight (no AI dependencies)

## CLI Commands: Gateway vs Node Execution

### Where Can CLI Commands Be Run?

| Command | On Gateway | On Node | Notes |
|---------|------------|---------|-------|
| `openclaw nodes status` | ✅ Works | ❌ Fails | Queries local registry |
| `openclaw nodes invoke` | ✅ Works | ❌ Fails | Sends command to Node |
| `openclaw devices list` | ✅ Works | ❌ Fails | Lists pairing requests |
| `openclaw node run` | ❌ Wrong role | ✅ Works | Node connects to Gateway |
| `openclaw gateway run` | ✅ Works | ❌ Wrong role | Gateway listens for Nodes |

**Best Practice**: Run all management commands on the **Gateway** machine.

### Why Node Cannot Run `nodes status`?

```
On Gateway:
  openclaw nodes status
      |
      v
  Reads local file ~/.openclaw/nodes/paired.json
      |
      v
  Returns result ✅

On Node:
  openclaw nodes status
      |
      v
  Detects gateway.mode=remote
      |
      v
  Tries to connect to Gateway via WebSocket
      |
      v
  Requires CLI authentication token (different from node run service token)
      |
      v
  Authentication fails ❌
```

## LLM Tool Calls vs CLI Commands

**Important**: When users send natural language via Telegram/Slack, the LLM does NOT translate to CLI commands. Instead, it calls **Tools**.

### How Natural Language Gets Processed

```
User (Telegram): "Show me the CPU usage of the Node"
        |
        v
Gateway AI Agent analyzes intent
        |
        v
LLM decides to call: nodes tool
        |
        +-- action: "run"
        +-- node: "54.82.26.182"
        +-- command: ["cat", "/proc/loadavg"]
        |
        v (WebSocket)
Node executes: cat /proc/loadavg
        |
        v
Returns: "0.15 0.10 0.05 1/234 12345"
        |
        v
LLM generates natural language reply: "The Node CPU load is..."
        |
        v
User receives reply
```

### nodes Tool Actions - Where They Execute

| Action | Executes On | Description |
|--------|-------------|-------------|
| `status` | **Gateway** | Query local Node registry |
| `describe` | **Gateway** | Get details of a specific Node |
| `pending` | **Gateway** | List pending pairing requests |
| `approve` | **Gateway** | Approve a pairing request |
| `reject` | **Gateway** | Reject a pairing request |
| `run` | **Node** | Execute shell command on Node |
| `camera_snap` | **Node** | Take a photo |
| `camera_clip` | **Node** | Record video |
| `screen_record` | **Node** | Record screen |
| `location_get` | **Node** | Get GPS location |
| `notify` | **Node** | Send notification |

### Examples: User Query → Tool Action → Execution Location

| User Query | Tool Call | Execution |
|------------|-----------|-----------|
| "List all Nodes" | `nodes(action=status)` | Gateway local |
| "Check CPU usage" | `nodes(action=run, command=["cat","/proc/loadavg"])` | Node remote |
| "Take a photo" | `nodes(action=camera_snap)` | Node remote |
| "Approve pairing" | `nodes(action=approve, requestId=xxx)` | Gateway local |
| "How much disk space?" | `nodes(action=run, command=["df","-h","/"])` | Node remote |

### Visual: Two Types of Operations

```
+-------------------------------------------------------------------------+
|                    TYPE 1: Gateway-Local Operations                     |
+-------------------------------------------------------------------------+
|                                                                         |
|  User: "List all Nodes" / "nodes status"                                |
|                                                                         |
|  +----------+    +---------+    +------------------+                    |
|  | Telegram |--->| Gateway |--->| nodes tool       |                    |
|  |   User   |    | AI+LLM  |    | action="status"  |                    |
|  +----------+    +---------+    +--------+---------+                    |
|                                          |                              |
|                                          v                              |
|                                 Query local registry                    |
|                                 ~/.openclaw/nodes/                      |
|                                          |                              |
|                                          v                              |
|                                 Return node list                        |
|                                 (NO command sent to Node!)              |
|                                                                         |
+-------------------------------------------------------------------------+
|                    TYPE 2: Node-Remote Operations                       |
+-------------------------------------------------------------------------+
|                                                                         |
|  User: "Check Node CPU usage"                                           |
|                                                                         |
|  +----------+    +---------+    +---------------------------+           |
|  | Telegram |--->| Gateway |--->| nodes tool                |           |
|  |   User   |    | AI+LLM  |    | action="run"              |           |
|  +----------+    +---------+    | command=["cat",           |           |
|                                 |   "/proc/loadavg"]        |           |
|                                 +-------------+-------------+           |
|                                               |                         |
|                                               v WebSocket               |
|                                 +---------------------------+           |
|                                 |           Node            |           |
|                                 |   Execute: system.run     |           |
|                                 |   cat /proc/loadavg       |           |
|                                 +-------------+-------------+           |
|                                               |                         |
|                                               v                         |
|                                 Return: "0.15 0.10 0.05"                |
|                                                                         |
+-------------------------------------------------------------------------+
```
