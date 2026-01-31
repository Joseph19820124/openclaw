#!/bin/bash
#
# OpenClaw 模拟 IM 工具
# 用于测试环境中模拟 Slack/Telegram 等即时通讯工具
#

# 配置
GATEWAY_HOST="44.217.250.149"
GATEWAY_PORT="18789"
NODE_IP="54.82.26.182"
SESSION_ID="sim-im-session-$(date +%s)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 设置 API Key
export ZAI_API_KEY="aeb5dc49d4bc45e790a8dacbe9bef17b.Ridz7zV1ctghiHMS"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$(dirname "$SCRIPT_DIR")"

# 加载 nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

cd "$OPENCLAW_DIR"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           OpenClaw 模拟 IM 工具 (测试环境)                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Gateway: $GATEWAY_HOST:$GATEWAY_PORT                              ║"
echo "║  Node:    $NODE_IP                                    ║"
echo "║  Model:   Z.AI GLM-4.6                                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  快捷命令:                                                    ║"
echo "║    cpu     - 查询 Node CPU 使用率                             ║"
echo "║    mem     - 查询 Node 内存使用率                             ║"
echo "║    disk    - 查询 Node 磁盘使用率                             ║"
echo "║    status  - 查询 Node 整体状态                               ║"
echo "║    nodes   - 列出所有已连接的 Node                            ║"
echo "║    exit    - 退出                                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 直接执行 Node 命令的函数
run_node_command() {
    local cmd="$1"
    echo -e "${YELLOW}[执行] ${cmd}${NC}"
    ./openclaw.mjs nodes invoke --node "$NODE_IP" --command system.run --params "{\"command\":$cmd}" --json 2>/dev/null | jq -r '.payload.stdout // .payload.stderr // "执行失败"'
}

# 发送消息给 Agent 的函数
send_to_agent() {
    local message="$1"
    echo -e "${BLUE}[Agent 处理中...]${NC}"
    ./openclaw.mjs agent --message "$message" --session-id "$SESSION_ID" --local 2>&1
}

# 主循环
while true; do
    echo ""
    echo -ne "${GREEN}[You]${NC} "
    read -r input

    # 检查退出
    if [[ "$input" == "exit" || "$input" == "quit" || "$input" == "q" ]]; then
        echo -e "${CYAN}再见！${NC}"
        break
    fi

    # 检查空输入
    if [[ -z "$input" ]]; then
        continue
    fi

    echo ""

    # 快捷命令处理
    case "$input" in
        cpu)
            echo -e "${CYAN}[Bot] 正在查询 Node ($NODE_IP) 的 CPU 使用率...${NC}"
            echo ""
            run_node_command '["cat","/proc/loadavg"]'
            echo ""
            echo -e "${YELLOW}Load Average 说明: 1分钟 5分钟 15分钟 运行进程/总进程 最后进程ID${NC}"
            ;;
        mem)
            echo -e "${CYAN}[Bot] 正在查询 Node ($NODE_IP) 的内存使用率...${NC}"
            echo ""
            run_node_command '["free","-h"]'
            ;;
        disk)
            echo -e "${CYAN}[Bot] 正在查询 Node ($NODE_IP) 的磁盘使用率...${NC}"
            echo ""
            run_node_command '["df","-h","/"]'
            ;;
        status)
            echo -e "${CYAN}[Bot] 正在查询 Node ($NODE_IP) 的整体状态...${NC}"
            echo ""
            echo "=== 系统运行时间 ==="
            run_node_command '["uptime"]'
            echo ""
            echo "=== CPU 负载 ==="
            run_node_command '["cat","/proc/loadavg"]'
            echo ""
            echo "=== 内存使用 ==="
            run_node_command '["free","-h"]'
            echo ""
            echo "=== 磁盘使用 ==="
            run_node_command '["df","-h","/"]'
            ;;
        nodes)
            echo -e "${CYAN}[Bot] 正在列出所有已连接的 Node...${NC}"
            echo ""
            ./openclaw.mjs nodes status 2>/dev/null
            ;;
        top)
            echo -e "${CYAN}[Bot] 正在获取 Node ($NODE_IP) 的 top 输出...${NC}"
            echo ""
            run_node_command '["top","-bn1","-o","%CPU"]' | head -20
            ;;
        help)
            echo -e "${CYAN}[Bot] 可用命令:${NC}"
            echo "  cpu     - 查询 CPU 负载"
            echo "  mem     - 查询内存使用"
            echo "  disk    - 查询磁盘使用"
            echo "  status  - 查询整体状态"
            echo "  nodes   - 列出所有 Node"
            echo "  top     - 查看进程列表"
            echo "  exit    - 退出"
            echo ""
            echo "  或者输入任意问题，由 AI 处理"
            ;;
        *)
            # 发送给 AI Agent 处理
            echo -e "${CYAN}[Bot]${NC}"
            send_to_agent "$input"
            ;;
    esac
done
