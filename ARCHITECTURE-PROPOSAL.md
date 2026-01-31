# OpenClaw Gateway + Node 架构方案 (Final)

## 概述

在 AWS us-east-1 区域部署 OpenClaw 分布式架构，包含一台 Gateway 服务器和一台 Node 服务器。

## 架构图

```
                         Internet
                            │
                            ▼
                    ┌───────────────┐
                    │  Elastic IP   │
                    │ (固定公网 IP)  │
                    └───────┬───────┘
                            │
    ┌───────────────────────┼─────────────────────────────┐
    │                 AWS us-east-1                        │
    │                                                      │
    │  ┌────────────────────────────────────────────────┐ │
    │  │         Security Group: openclaw-sg            │ │
    │  │         Ports: 22, 443 (TLS)                   │ │
    │  └────────────────────────────────────────────────┘ │
    │                                                      │
    │  ┌─────────────────┐        ┌─────────────────┐    │
    │  │   openclaw-gw   │        │  openclaw-node  │    │
    │  │   (t3.medium)   │        │   (t3.small)    │    │
    │  │                 │        │                 │    │
    │  │ ┌─────────────┐ │        │ ┌─────────────┐ │    │
    │  │ │  Gateway    │ │◄──TLS──│ │    Node     │ │    │
    │  │ │  :443 (wss) │ │        │ │  (Client)   │ │    │
    │  │ └─────────────┘ │        │ └─────────────┘ │    │
    │  │                 │        │                 │    │
    │  │ ┌─────────────┐ │        │ ┌─────────────┐ │    │
    │  │ │  systemd    │ │        │ │  systemd    │ │    │
    │  │ │  service    │ │        │ │  service    │ │    │
    │  │ └─────────────┘ │        │ └─────────────┘ │    │
    │  │                 │        │                 │    │
    │  │ ┌─────────────┐ │        │ ┌─────────────┐ │    │
    │  │ │ CloudWatch  │ │        │ │ CloudWatch  │ │    │
    │  │ │   Agent     │ │        │ │   Agent     │ │    │
    │  │ └─────────────┘ │        │ └─────────────┘ │    │
    │  └─────────────────┘        └─────────────────┘    │
    │                                                      │
    └──────────────────────────────────────────────────────┘
```

## 资源规划

### EC2 实例

| 名称 | 类型 | 用途 | 端口 | EBS 卷 |
|------|------|------|------|--------|
| openclaw-gw | t3.medium (2 vCPU, 4GB) | Gateway 服务器 | 22 (SSH), 443 (WSS/TLS) | 100GB gp3 |
| openclaw-node | t3.small (2 vCPU, 2GB) | Node 客户端 | 22 (SSH) | 100GB gp3 |

### 网络配置

| 资源 | 配置 |
|------|------|
| VPC | 使用默认 VPC |
| Security Group | openclaw-sg |
| Elastic IP | 绑定到 openclaw-gw |
| Inbound Rules | SSH (22), HTTPS/WSS (443) |

### SSH Key Pair

| 项目 | 配置 |
|------|------|
| Key Name | openclaw-key |
| Type | RSA 2048-bit |
| 存储位置 | ~/.ssh/openclaw-key.pem |

### AMI & 软件

| 项目 | 选择 |
|------|------|
| AMI | Amazon Linux 2023 (最新) |
| Node.js | v22+ (通过 nvm 安装) |
| Package Manager | pnpm v10+ |
| CloudWatch Agent | amazon-cloudwatch-agent |

### 安装方式

| 项目 | 方式 |
|------|------|
| OpenClaw | **源码编译** - 从 GitHub 克隆后 `pnpm install && pnpm build` |
| 仓库地址 | https://github.com/Joseph19820124/openclaw.git |

## 部署流程

### 阶段 1: 基础设施准备

1. **创建 SSH Key Pair** `openclaw-key`

2. **创建 Security Group** `openclaw-sg`
   - Inbound: SSH (22) from 0.0.0.0/0
   - Inbound: HTTPS (443) from 0.0.0.0/0 (TLS Gateway)
   - Outbound: All traffic

3. **创建 IAM Role** `openclaw-ec2-role`
   - Policy: CloudWatchAgentServerPolicy
   - Policy: AmazonSSMManagedInstanceCore

4. **启动 EC2 实例**
   - openclaw-gw (t3.medium) with IAM Role
   - openclaw-node (t3.small) with IAM Role

5. **分配 Elastic IP** 并绑定到 openclaw-gw

### 阶段 2: Gateway 服务器配置 (openclaw-gw)

```bash
# 1. 安装依赖
sudo dnf update -y
sudo dnf install -y git openssl

# 2. 安装 Node.js 22
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22

# 3. 安装 pnpm
npm install -g pnpm

# 4. 克隆并构建 OpenClaw
git clone https://github.com/Joseph19820124/openclaw.git
cd openclaw
pnpm install
pnpm build

# 5. 生成自签名 TLS 证书
sudo mkdir -p /etc/openclaw/certs
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/openclaw/certs/server.key \
  -out /etc/openclaw/certs/server.crt \
  -subj "/CN=openclaw-gateway"
sudo chmod 600 /etc/openclaw/certs/server.key

# 6. 安装 CloudWatch Agent
sudo dnf install -y amazon-cloudwatch-agent
```

### 阶段 3: Gateway systemd 服务

**/etc/systemd/system/openclaw-gateway.service**
```ini
[Unit]
Description=OpenClaw Gateway Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/openclaw
Environment=NODE_ENV=production
Environment=PATH=/home/ec2-user/.nvm/versions/node/v22.*/bin:/usr/bin:/bin
ExecStart=/home/ec2-user/openclaw/openclaw.mjs gateway \
  --bind lan \
  --port 443 \
  --tls \
  --tls-cert /etc/openclaw/certs/server.crt \
  --tls-key /etc/openclaw/certs/server.key
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable openclaw-gateway
sudo systemctl start openclaw-gateway
```

### 阶段 4: Node 服务器配置 (openclaw-node)

```bash
# 1. 安装依赖 (同 Gateway)
sudo dnf update -y
sudo dnf install -y git
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22
npm install -g pnpm

# 2. 克隆并构建 OpenClaw
git clone https://github.com/Joseph19820124/openclaw.git
cd openclaw
pnpm install
pnpm build

# 3. 安装 CloudWatch Agent
sudo dnf install -y amazon-cloudwatch-agent
```

### 阶段 5: Node systemd 服务

**/etc/systemd/system/openclaw-node.service**
```ini
[Unit]
Description=OpenClaw Node Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/openclaw
Environment=NODE_ENV=production
Environment=PATH=/home/ec2-user/.nvm/versions/node/v22.*/bin:/usr/bin:/bin
ExecStart=/home/ec2-user/openclaw/openclaw.mjs connect \
  --gateway wss://<ELASTIC_IP>:443 \
  --insecure
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable openclaw-node
sudo systemctl start openclaw-node
```

### 阶段 6: CloudWatch 监控配置

**/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json**
```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "OpenClaw",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_active", "cpu_usage_idle"],
        "totalcpu": true
      },
      "mem": {
        "measurement": ["mem_used_percent", "mem_available"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"]
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/ec2-user/.openclaw/logs/*.log",
            "log_group_name": "/openclaw/application",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/openclaw/system",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
```

### 阶段 7: CloudWatch 告警

| 告警名称 | 指标 | 阈值 | 周期 |
|---------|------|------|------|
| OpenClaw-GW-CPU-High | CPUUtilization | > 80% | 5 分钟 |
| OpenClaw-GW-Memory-High | mem_used_percent | > 85% | 5 分钟 |
| OpenClaw-GW-StatusCheck | StatusCheckFailed | >= 1 | 1 分钟 |
| OpenClaw-Node-CPU-High | CPUUtilization | > 80% | 5 分钟 |
| OpenClaw-Node-StatusCheck | StatusCheckFailed | >= 1 | 1 分钟 |

## 配置文件

### Gateway 配置 (~/.openclaw/openclaw.json)

```json
{
  "gateway": {
    "mode": "server",
    "bind": "lan",
    "port": 443,
    "tls": {
      "enabled": true,
      "cert": "/etc/openclaw/certs/server.crt",
      "key": "/etc/openclaw/certs/server.key"
    },
    "auth": {
      "enabled": true,
      "token": "<GENERATED_TOKEN>"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace"
    }
  }
}
```

### Node 配置 (~/.openclaw/openclaw.json)

```json
{
  "gateway": {
    "mode": "client",
    "remote": "wss://<ELASTIC_IP>:443",
    "token": "<GATEWAY_TOKEN>",
    "insecure": true
  }
}
```

## 安全措施

| 措施 | 说明 |
|------|------|
| TLS 加密 | 所有 Gateway 通信使用 WSS (WebSocket Secure) |
| Token 认证 | Node 连接需携带认证 Token |
| Security Group | 仅开放必要端口 (22, 443) |
| IAM Role | 最小权限原则，仅 CloudWatch 权限 |
| systemd | 服务自动重启，故障恢复 |
| 自签名证书 | 初期使用，生产环境建议使用 ACM 或 Let's Encrypt |

## 成本估算 (us-east-1)

| 资源 | 单价 | 月费用 (估算) |
|------|------|--------------|
| t3.medium (on-demand) | $0.0416/hr | ~$30/月 |
| t3.small (on-demand) | $0.0208/hr | ~$15/月 |
| EBS (100GB gp3 x2) | $0.08/GB | ~$16/月 |
| Elastic IP (使用中) | $0.005/hr | ~$3.6/月 |
| CloudWatch Logs (5GB) | $0.50/GB | ~$2.5/月 |
| CloudWatch Metrics | 基本免费 | ~$0 |
| **总计** | | **~$67/月** |

## 实施步骤清单

- [ ] 1. 创建 SSH Key Pair `openclaw-key`
- [ ] 2. 创建 IAM Role `openclaw-ec2-role`
- [ ] 3. 创建 Security Group `openclaw-sg`
- [ ] 4. 启动 EC2: openclaw-gw (t3.medium)
- [ ] 5. 启动 EC2: openclaw-node (t3.small)
- [ ] 6. 分配并绑定 Elastic IP
- [ ] 7. 配置 openclaw-gw (安装软件、TLS 证书、systemd)
- [ ] 8. 配置 openclaw-node (安装软件、systemd)
- [ ] 9. 配置 CloudWatch Agent (两台)
- [ ] 10. 创建 CloudWatch 告警
- [ ] 11. 验证 Node 注册到 Gateway
- [ ] 12. 端到端测试

## 验证命令

```bash
# 在 Gateway 上检查服务状态
sudo systemctl status openclaw-gateway

# 在 Node 上检查服务状态
sudo systemctl status openclaw-node

# 检查 Gateway 日志
journalctl -u openclaw-gateway -f

# 检查已注册的节点
cd ~/openclaw && ./openclaw.mjs nodes list

# 测试 TLS 连接
openssl s_client -connect <ELASTIC_IP>:443
```

---

**确认后我将开始执行上述 12 个实施步骤。**
