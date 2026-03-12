#!/bin/bash
#
# Hypervisor Test Framework - 本地测试脚本
# 此脚本可独立运行，也可被各组件调用
#
# 用法:
#   ./tests.sh                           # 运行所有测试
#   ./tests.sh --target axvisor-qemu     # 仅测试指定目标
#   ./tests.sh --config /path/to/.test-config.json
#   ./tests.sh --component-dir /path/to/component
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"
COMPONENT_DIR=""
CONFIG_FILE=""
TEST_TARGET="all"
VERBOSE=false
CLEANUP=true
DRY_RUN=false
PARALLEL=false
OUTPUT_DIR=""
USE_GIT=false
GIT_BRANCH=""
CLEAN_RESULTS=false
AUTO_MODE=false
LIST_JSON=false
LIST_AUTO=false
USE_FS_MODE=false
PRINT_OUTPUT=false

# 帮助信息
show_help() {
    cat << 'EOF'
Hypervisor Test Framework - 本地测试脚本

用法:
  tests.sh [选项]

选项:
  -c, --component-dir DIR    组件目录 (默认: 当前目录)
  -f, --config FILE          配置文件路径 (可选，默认使用内置测试目标)
  -t, --target TARGET        测试目标: all, axvisor-qemu, starry, 或具体目标名 (默认: all)
  -o, --output DIR           输出目录 (默认: COMPONENT_DIR/test-results)
  -v, --verbose              详细输出
  --no-cleanup               不清理临时文件
  --dry-run                  仅显示将要执行的命令
  --parallel                 并行执行测试 (默认顺序执行)
  --from-git                 从 git 仓库拉取代码 (默认从 crates.io 下载)
  --branch BRANCH            指定 git 分支 (仅与 --from-git 一起使用)
  --clean                    清理测试生成的 test-results 目录
  --auto                     根据 rust-toolchain.toml 中的 targets 自动选择测试
  --list-auto                列出自动检测的测试目标 (JSON 格式)
  --list-json                列出所有测试目标 (JSON 格式，用于 CI matrix)
  --fs                       使用文件系统模式，不修改配置文件
  --print                    打印 U-Boot 和串口输出到命令行
  -h, --help                 显示此帮助

测试目标:
  list                       列出所有可用的测试用例
  all                        运行所有测试
  axvisor-qemu               运行所有 axvisor QEMU 测试
  axvisor-board              运行所有 axvisor Board 测试
  starry                     运行所有 starry 测试
  axvisor-qemu-aarch64-arceos     测试 axvisor 在 QEMU aarch64 上的 ArceOS 镜像
  axvisor-qemu-aarch64-linux      测试 axvisor 在 QEMU aarch64 上的 Linux 镜像
  axvisor-qemu-x86_64-nimbos      测试 axvisor 在 QEMU x86_64 上的 NimbOS 镜像
  axvisor-board-phytiumpi-arceos  测试 axvisor 在 phytiumpi 开发板上的 ArceOS 镜像
  axvisor-board-phytiumpi-linux   测试 axvisor 在 phytiumpi 开发板上的 Linux 镜像
  axvisor-board-roc-rk3568-pc-arceos  测试 axvisor 在 roc-rk3568-pc 开发板上的 ArceOS 镜像
  axvisor-board-roc-rk3568-pc-linux   测试 axvisor 在 roc-rk3568-pc 开发板上的 Linux 镜像
  starry-riscv64             测试 starry 在 riscv64 架构下
  starry-loongarch64         测试 starry 在 loongarch64 架构下
  starry-aarch64             测试 starry 在 aarch64 架构下
  starry-x86_64              测试 starry 在 x86_64 架构下

镜像下载:
  镜像将从 https://github.com/arceos-hypervisor/axvisor-guest/releases/v0.0.22 自动下载
  存储位置: /tmp/.axvisor-images

示例:
  tests.sh                                    # 在当前目录运行所有测试
  tests.sh --auto                             # 根据 rust-toolchain.toml 自动选择测试
  tests.sh -t axvisor-qemu                    # 仅运行 axvisor QEMU 测试
  tests.sh -t axvisor-board                   # 仅运行 axvisor Board 测试
  tests.sh -t starry-aarch64                  # 仅运行 starry aarch64 测试
  tests.sh -t axvisor-board-phytiumpi-arceos  # 仅运行 phytiumpi ArceOS 测试
  tests.sh --dry-run -v                       # 显示将要执行的命令

EOF
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--component-dir)
                COMPONENT_DIR="$2"
                shift 2
                ;;
            -f|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -t|--target)
                TEST_TARGET="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --parallel)
                PARALLEL=true
                shift
                ;;
            --from-git)
                USE_GIT=true
                shift
                ;;
            --branch)
                GIT_BRANCH="$2"
                shift 2
                ;;
            --clean)
                CLEAN_RESULTS=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --list-json)
                LIST_JSON=true
                shift
                ;;
            --list-auto)
                LIST_AUTO=true
                AUTO_MODE=true
                shift
                ;;
            --fs)
                USE_FS_MODE=true
                shift
                ;;
            --print)
                PRINT_OUTPUT=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 日志函数
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { 
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

error() { log_error "$1"; exit 1; }

# 从 rust-toolchain.toml 中提取 targets 并映射到架构
detect_targets_from_toolchain() {
    local toolchain_file="$COMPONENT_DIR/rust-toolchain.toml"
    local detected_archs=()

    if [ ! -f "$toolchain_file" ]; then
        log_warn "未找到 rust-toolchain.toml，使用所有架构"
        echo "all"
        return
    fi

    # 提取 targets 数组
    local targets=$(grep -A 20 '^targets' "$toolchain_file" 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' || true)

    if [ -z "$targets" ]; then
        log_warn "rust-toolchain.toml 中未找到 targets，使用所有架构"
        echo "all"
        return
    fi

    log_debug "从 rust-toolchain.toml 检测到 targets:"

    # 解析每个 target 并映射到架构
    while IFS= read -r target; do
        [ -z "$target" ] && continue
        log_debug "  - $target"

        case "$target" in
            *aarch64*)
                if [[ " ${detected_archs[*]} " != *" aarch64 "* ]]; then
                    detected_archs+=("aarch64")
                fi
                ;;
            *x86_64*)
                if [[ " ${detected_archs[*]} " != *" x86_64 "* ]]; then
                    detected_archs+=("x86_64")
                fi
                ;;
            *riscv64*)
                if [[ " ${detected_archs[*]} " != *" riscv64 "* ]]; then
                    detected_archs+=("riscv64")
                fi
                ;;
            *loongarch64*)
                if [[ " ${detected_archs[*]} " != *" loongarch64 "* ]]; then
                    detected_archs+=("loongarch64")
                fi
                ;;
        esac
    done <<< "$targets"

    if [ ${#detected_archs[@]} -eq 0 ]; then
        log_warn "无法从 targets 识别架构，使用所有架构"
        echo "all"
        return
    fi

    log "检测到的架构: ${detected_archs[*]}"
    echo "${detected_archs[*]}"
}

# 检查依赖
check_dependencies() {
    log "检查依赖..."

    local missing=()

    # 检查 jq
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    # 检查 git
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    # 检查 cargo
    if ! command -v cargo &> /dev/null; then
        missing+=("cargo (Rust)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少依赖: ${missing[*]}\n请安装后重试。"
    fi

    # 检查并安装 cargo-clone
    if ! command -v cargo-clone &> /dev/null && ! cargo clone --help &> /dev/null; then
        log "安装 cargo-clone..."
        cargo install cargo-clone
    fi

    log_success "依赖检查通过"
}

# 默认测试目标
DEFAULT_TARGETS='[
  {
    "name": "axvisor-qemu-aarch64-arceos",
    "type": "qemu",
    "arch": "aarch64",
    "repo": {"url": "https://github.com/arceos-hypervisor/axvisor", "branch": "master"},
    "build": {"command": "", "timeout_minutes": 15},
    "test": {
      "command": "cargo xtask qemu",
      "build_config": "configs/board/qemu-aarch64.toml",
      "qemu_config": ".github/workflows/qemu-aarch64.toml",
      "vmconfigs": "configs/vms/arceos-aarch64-qemu-smp1.toml",
      "vmimage_name": "qemu_aarch64_arceos,qemu_aarch64_arceos"
    },
    "patch": {"path_template": "../component"}
  },
  {
    "name": "axvisor-qemu-aarch64-linux",
    "type": "qemu",
    "arch": "aarch64",
    "repo": {"url": "https://github.com/arceos-hypervisor/axvisor", "branch": "master"},
    "build": {"command": "", "timeout_minutes": 15},
    "test": {
      "command": "cargo xtask qemu",
      "build_config": "configs/board/qemu-aarch64.toml",
      "qemu_config": ".github/workflows/qemu-aarch64.toml",
      "vmconfigs": "configs/vms/linux-aarch64-qemu-smp1.toml",
      "vmimage_name": "qemu_aarch64_linux"
    },
    "patch": {"path_template": "../component"}
  },
  {
    "name": "axvisor-qemu-x86_64-nimbos",
    "type": "qemu",
    "arch": "x86_64",
    "repo": {"url": "https://github.com/arceos-hypervisor/axvisor", "branch": "master"},
    "build": {"command": "", "timeout_minutes": 15},
    "test": {
      "command": "cargo xtask qemu",
      "build_config": "configs/board/qemu-x86_64.toml",
      "qemu_config": ".github/workflows/qemu-x86_64.toml",
      "vmconfigs": "configs/vms/nimbos-x86_64-qemu-smp1.toml",
      "vmimage_name": "qemu_x86_64_nimbos"
    },
    "patch": {"path_template": "../component"}
  },
  {
    "name": "starry-riscv64",
    "type": "qemu",
    "arch": "riscv64",
    "repo": {"url": "https://github.com/Starry-OS/StarryOS", "branch": "main"},
    "build": {"command": "make build", "timeout_minutes": 15},
    "test": {},
    "patch": {"path_template": "../component"}
  },
  {
    "name": "starry-loongarch64",
    "type": "qemu",
    "arch": "loongarch64",
    "repo": {"url": "https://github.com/Starry-OS/StarryOS", "branch": "main"},
    "build": {"command": "make build", "timeout_minutes": 15},
    "test": {},
    "patch": {"path_template": "../component"}
  },
  {
    "name": "starry-aarch64",
    "type": "qemu",
    "arch": "aarch64",
    "repo": {"url": "https://github.com/Starry-OS/StarryOS", "branch": "main"},
    "build": {"command": "make build", "timeout_minutes": 15},
    "test": {},
    "patch": {"path_template": "../component"}
  },
  {
    "name": "starry-x86_64",
    "type": "qemu",
    "arch": "x86_64",
    "repo": {"url": "https://github.com/Starry-OS/StarryOS", "branch": "main"},
    "build": {"command": "make build", "timeout_minutes": 15},
    "test": {},
    "patch": {"path_template": "../component"}
  },
  {
    "name": "axvisor-board-phytiumpi-arceos",
    "type": "board",
    "arch": "aarch64",
    "board": "phytiumpi",
    "repo": {"url": "https://github.com/arceos-hypervisor/axvisor", "branch": "master"},
    "build": {"command": "", "timeout_minutes": 15},
    "test": {
      "command": "cargo xtask uboot",
      "build_config": "configs/board/phytiumpi.toml",
      "uboot_config": ".github/workflows/uboot.toml",
      "vmconfigs": "configs/vms/arceos-aarch64-e2000-smp1.toml",
      "vmimage_name": "phytiumpi_arceos,phytiumpi_linux",
      "bin_dir": "/tmp/tftp"
    },
    "patch": {"path_template": "../component"}
  },
  {
    "name": "axvisor-board-phytiumpi-linux",
    "type": "board",
    "arch": "aarch64",
    "board": "phytiumpi",
    "repo": {"url": "https://github.com/arceos-hypervisor/axvisor", "branch": "master"},
    "build": {"command": "", "timeout_minutes": 15},
    "test": {
      "command": "cargo xtask uboot",
      "build_config": "configs/board/phytiumpi.toml",
      "uboot_config": ".github/workflows/uboot.toml",
      "vmconfigs": "configs/vms/linux-aarch64-e2000-smp1.toml",
      "vmimage_name": "phytiumpi_linux",
      "bin_dir": "/tmp/tftp"
    },
    "patch": {"path_template": "../component"}
  },
  {
    "name": "axvisor-board-roc-rk3568-pc-arceos",
    "type": "board",
    "arch": "aarch64",
    "board": "roc-rk3568-pc",
    "repo": {"url": "https://github.com/arceos-hypervisor/axvisor", "branch": "master"},
    "build": {"command": "", "timeout_minutes": 15},
    "test": {
      "command": "cargo xtask uboot",
      "build_config": "configs/board/roc-rk3568-pc.toml",
      "uboot_config": ".github/workflows/uboot.toml",
      "vmconfigs": "configs/vms/arceos-aarch64-rk3568-smp1.toml",
      "vmimage_name": "roc-rk3568-pc_arceos,roc-rk3568-pc_linux",
      "bin_dir": "/tmp/tftp"
    },
    "patch": {"path_template": "../component"}
  },
  {
    "name": "axvisor-board-roc-rk3568-pc-linux",
    "type": "board",
    "arch": "aarch64",
    "board": "roc-rk3568-pc",
    "repo": {"url": "https://github.com/arceos-hypervisor/axvisor", "branch": "master"},
    "build": {"command": "", "timeout_minutes": 15},
    "test": {
      "command": "cargo xtask uboot",
      "build_config": "configs/board/roc-rk3568-pc.toml",
      "uboot_config": ".github/workflows/uboot.toml",
      "vmconfigs": "configs/vms/linux-aarch64-rk3568-smp1.toml",
      "vmimage_name": "roc-rk3568-pc_linux",
      "bin_dir": "/tmp/tftp"
    },
    "patch": {"path_template": "../component"}
  }
]'

# 加载配置
load_config() {
    # 确定组件目录
    if [ -z "$COMPONENT_DIR" ]; then
        COMPONENT_DIR="$(pwd)"
    fi
    
    # 尝试查找配置文件（可选）
    if [ -z "$CONFIG_FILE" ]; then
        if [ -f "$COMPONENT_DIR/.github/config.json" ]; then
            CONFIG_FILE="$COMPONENT_DIR/.github/config.json"
        elif [ -f "$COMPONENT_DIR/.test-config.json" ]; then
            CONFIG_FILE="$COMPONENT_DIR/.test-config.json"
        fi
    fi
    
    # 检测 crate 名称（从 Cargo.toml）
    if [ -f "$COMPONENT_DIR/Cargo.toml" ]; then
        COMPONENT_CRATE=$(grep '^name = ' "$COMPONENT_DIR/Cargo.toml" | head -1 | sed 's/name = "\(.*\)"/\1/' || basename "$COMPONENT_DIR")
    else
        COMPONENT_CRATE=$(basename "$COMPONENT_DIR")
    fi
    COMPONENT_NAME="$COMPONENT_CRATE"
    
    # 如果有配置文件，则使用配置文件
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        log "加载配置: $CONFIG_FILE"
        CONFIG=$(cat "$CONFIG_FILE")
        # 从配置文件获取组件信息
        local config_name=$(echo "$CONFIG" | jq -r '.component.name // empty')
        local config_crate=$(echo "$CONFIG" | jq -r '.component.crate_name // empty')
        [ -n "$config_name" ] && COMPONENT_NAME="$config_name"
        [ -n "$config_crate" ] && COMPONENT_CRATE="$config_crate"
        
        # 检查配置文件是否包含 test_targets
        local has_targets=$(echo "$CONFIG" | jq 'has("test_targets")')
        if [ "$has_targets" != "true" ]; then
            log "配置文件不包含 test_targets，使用默认测试目标"
            CONFIG="{\"component\":{\"name\":\"$COMPONENT_NAME\",\"crate_name\":\"$COMPONENT_CRATE\"},\"test_targets\":$DEFAULT_TARGETS}"
        fi
    else
        log "未找到配置文件，使用默认测试目标"
        CONFIG="{\"component\":{\"name\":\"$COMPONENT_NAME\",\"crate_name\":\"$COMPONENT_CRATE\"},\"test_targets\":$DEFAULT_TARGETS}"
    fi
    
    log_debug "组件: $COMPONENT_NAME ($COMPONENT_CRATE)"
}

# 设置输出目录
setup_output() {
    if [ -z "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="$COMPONENT_DIR/test-results"
    fi

    sudo mkdir -p "$OUTPUT_DIR/logs"
    sudo chmod -R 777 "$OUTPUT_DIR"
    log_debug "输出目录: $OUTPUT_DIR"
}

# 控制开发板电源（通过 mbpoll）
control_board_power() {
    local board_name=$1
    local action=$2  # "on" 或 "off"
    local power_serial=""
    
    # 根据开发板类型确定电源控制串口
    case "$board_name" in
        phytiumpi)
            power_serial="/dev/ttyUSB1"
            ;;
        roc-rk3568-pc)
            power_serial="/dev/ttyUSB2"
            ;;
        *)
            log_debug "  未知开发板类型: $board_name，跳过电源控制"
            return 0
            ;;
    esac
    
    # 检查 mbpoll 是否安装
    if ! command -v mbpoll &> /dev/null; then
        return 0
    fi
    
    # 检查串口是否存在
    if [ ! -e "$power_serial" ]; then
        log_warn "  电源控制串口不存在: $power_serial"
        return 0
    fi
    
    # 执行电源控制
    if [ "$action" == "on" ]; then
        mbpoll -m rtu -a 1 -r 1 -t 0 -b 38400 -P none -v "$power_serial" 0
        sleep 3
        log "  给开发板上电... ($power_serial)"
        mbpoll -m rtu -a 1 -r 1 -t 0 -b 38400 -P none -v "$power_serial" 1
    elif [ "$action" == "off" ]; then
        log "  给开发板下电... ($power_serial)"
        mbpoll -m rtu -a 1 -r 1 -t 0 -b 38400 -P none -v "$power_serial" 0 &>/dev/null || true
    fi
}

# 清理开发板测试资源
cleanup_board_resources() {
    local board_name=$1
    local test_dir=$2
    
    log "  清理测试资源..."
    
    # 1. 关闭开发板电源
    control_board_power "$board_name" "off"
    
    # 2. 杀掉可能残留的 cargo-osrun 进程
    local pids=$(ps aux | grep -E "cargo-osr|cargo osr" | grep -v grep | awk '{print $2}')
    if [ -n "$pids" ]; then
        for pid in $pids; do
            log_debug "    关闭残留进程: PID=$pid"
            kill -9 $pid 2>/dev/null || true
        done
    fi
    
    # 3. 释放串口
    local uboot_toml_file="$COMPONENT_DIR/.uboot.toml"
    if [ -f "$uboot_toml_file" ]; then
        local serial_port=$(jq -r ".boards[\"$board_name\"].serial // empty" "$uboot_toml_file" 2>/dev/null)
        if [ -n "$serial_port" ] && [ -e "$serial_port" ]; then
            local serial_pids=$(sudo lsof -ti "$serial_port" 2>/dev/null || true)
            if [ -n "$serial_pids" ]; then
                for pid in $serial_pids; do
                    log_debug "    释放串口 $serial_port: PID=$pid"
                    sudo kill -9 $pid 2>/dev/null || true
                done
            fi
        fi
    fi
    
    # 等待资源释放
    sleep 2
    log "  资源清理完成"
}

# 运行命令并监控输出，检测成功/失败标识符
run_with_success_detection() {
    local cmd="$1"
    local timeout_minutes="$2"
    local log_file="$3"
    local board_name="${4:-}"
    local test_dir="${5:-}"
    local success_patterns=()
    local error_patterns=()

    # 定义成功标识符模式（支持通配符）
    success_patterns+=("Welcome to")
    success_patterns+=("test pass!")
    success_patterns+=("All tests passed!")
    success_patterns+=("simple_sleep passed!")
    success_patterns+=("Hello, world!")
    success_patterns+=("root@firefly:~#")
    success_patterns+=("root@phytium-Ubuntu:~#")
    success_patterns+=("Set hostname to")
    success_patterns+=("starry:~#")
    success_patterns+=("Last login:")
    success_patterns+=("Booting kernel with command")
    # 定义错误标识符模式
    error_patterns+=("error[")
    error_patterns+=("FAILED")
    error_patterns+=("panicked")
    error_patterns+=("segmentation fault")
    error_patterns+=("core dumped")
    
    # 特殊模式：等待开发板上电
    local power_on_done=false
    local power_on_time=""

    # 创建临时文件来存储状态
    local status_file=$(mktemp)
    local power_flag_file=$(mktemp)
    echo "running" > "$status_file"
    echo "false" > "$power_flag_file"

    # 使用 timeout 运行命令，同时监控输出
    local pid=""
    local fifo=$(mktemp -u)
    mkfifo "$fifo"

    # 启动命令并将输出重定向到管道
    eval "$cmd" < /dev/null > "$fifo" 2>&1 &
    pid=$!

    # 在后台读取管道并检测成功/错误标识符
    (
        while IFS= read -r line; do
            # 输出到日志
            echo "$line" >> "$log_file"
            
            # 根据 --print 选项决定是否输出到标准输出
            [[ "$PRINT_OUTPUT" == true ]] && echo "$line"
            
            # 检测是否等待开发板上电
            if [[ "$line" == *"Waiting for board on power or reset"* ]]; then
                if [ "$power_on_done" == false ] && [ -n "$board_name" ]; then
                    power_on_done=true
                    echo "true" > "$power_flag_file"
                    echo "$(date +%s)" >> "$power_flag_file"
                    # 提示用户上电
                    log "  准备就绪，请给开发板上电…"
                    # 执行上电命令
                    control_board_power "$board_name" "on"
                fi
            fi

            # 检测是否匹配任何错误标识符（优先检测错误）
            for pattern in "${error_patterns[@]}"; do
                if [[ "$line" == *"$pattern"* ]]; then
                    echo "error:$pattern" > "$status_file"
                    kill $pid 2>/dev/null || true
                    exit 0
                fi
            done

            # 检测是否匹配任何成功标识符
            for pattern in "${success_patterns[@]}"; do
                if [[ "$line" == *"$pattern"* ]]; then
                    echo "success" > "$status_file"
                    kill $pid 2>/dev/null || true
                    exit 0
                fi
            done
        done < "$fifo"
    ) &
    local monitor_pid=$!

    # 等待主命令完成
    wait $pid 2>/dev/null || true
    local main_exit_code=$?

    # 对于开发板测试，主命令可能在 U-Boot 启动后就退出了
    # 此时应该继续监控串口输出，等待内核启动完成
    local is_powered_on=$(head -1 "$power_flag_file")
    if [ "$is_powered_on" == "true" ] && [ -n "$board_name" ]; then
        local power_on_timestamp=$(tail -1 "$power_flag_file")
        local current_time=$(date +%s)
        local elapsed=$((current_time - power_on_timestamp))
        local remaining_time=$((timeout_minutes * 60 - elapsed))
        
        if [ $remaining_time -gt 0 ]; then
            log "  U-Boot 阶段完成，继续监控串口输出 (剩余 ${remaining_time}s)..."
            
            # 从 .uboot.json 获取串口设备
            local uboot_json_file="$COMPONENT_DIR/.uboot.json"
            local serial_port=""
            if [ -f "$uboot_json_file" ]; then
                serial_port=$(jq -r ".boards[\"$board_name\"].serial // empty" "$uboot_json_file" 2>/dev/null)
            fi
            
            # 如果找到了串口设备，继续读取串口输出
            if [ -n "$serial_port" ] && [ -e "$serial_port" ]; then
                
                # 等待串口设备可用（cargo osrun 退出后释放串口）
                local wait_count=0
                while [ $wait_count -lt 10 ]; do
                    if ! lsof "$serial_port" &>/dev/null; then
                        break
                    fi
                    sleep 1
                    ((wait_count++))
                done       
                
                # 保存当前终端设置
                local saved_stty=$(stty -g 2>/dev/null) || true
                
                # 根据 --print 选项决定是否打印到标准输出
                if [[ "$PRINT_OUTPUT" == true ]]; then
                    timeout $remaining_time cat "$serial_port" 2>/dev/null | tee -a "$log_file" &
                else
                    timeout $remaining_time cat "$serial_port" 2>/dev/null >> "$log_file" &
                fi
                local serial_pid=$!
                
                # 监控日志文件检测成功/失败标识符
                local extra_wait=$remaining_time
                while [ $extra_wait -gt 0 ]; do
                    if grep -qE "Welcome to|test pass!|All tests passed!|Hello, world!|root@firefly:~#|Set hostname to" "$log_file" 2>/dev/null; then
                        echo -ne "\r\033[K"  # 清除当前行
                        log "  检测到成功标识符!"
                        echo "success" > "$status_file"
                        break
                    fi
                    if grep -qE "FAILED|panicked|segmentation fault|core dumped" "$log_file" 2>/dev/null; then
                        echo -ne "\r\033[K"  # 清除当前行
                        log "  检测到错误标识符!"
                        echo "error:detected" > "$status_file"
                        break
                    fi
                    sleep 1
                    ((extra_wait--))
                done
                
                # 终止串口读取进程
                kill $serial_pid 2>/dev/null || true
                sleep 0.5
                pkill -9 -P $serial_pid 2>/dev/null || true
                kill -9 $serial_pid 2>/dev/null || true
                
                # 恢复终端设置
                if [ -n "$saved_stty" ]; then
                    stty "$saved_stty" 2>/dev/null || true
                fi
                echo -ne "\r\033[K"  # 清除当前行，确保后续输出整齐
            else
                # 没有串口设备，只能等待
                log_warn "  未找到串口设备配置"
            fi
        fi
    fi

    # 等待监控进程完成
    wait $monitor_pid 2>/dev/null || true

    # 确保终端恢复正常（双重保险）
    stty sane 2>/dev/null || true

    # 读取状态
    local status=$(cat "$status_file")

    # 清理
    rm -f "$fifo" "$status_file" "$power_flag_file"
    
    # 如果是开发板测试，清理资源（关闭电源、释放串口等）
    if [ -n "$board_name" ] && [ -n "$test_dir" ]; then
        cleanup_board_resources "$board_name" "$test_dir"
    fi

    # 根据状态返回结果
    if [[ "$status" == error:* ]]; then
        local pattern=${status#error:}
        return 1
    elif [ "$status" = "success" ]; then
        return 0
    elif [ $main_exit_code -eq 124 ]; then
        return 124
    else
        # 检查是否是因为检测到成功标识符而结束
        if [ "$status" = "success" ]; then
            return 0
        fi
        # 进程退出但没有检测到成功标识符，视为失败
        return 1
    fi
}

# 获取要测试的目标
get_test_targets() {
    local targets=()

    if [ "$AUTO_MODE" == true ]; then
        # 自动模式：根据 rust-toolchain.toml 中的 targets 选择测试
        local archs=$(detect_targets_from_toolchain)

        if [ "$archs" == "all" ]; then
            # 无法识别架构，运行所有测试
            local count=$(echo "$CONFIG" | jq '.test_targets | length')
            for ((i=0; i<count; i++)); do
                targets+=("$(echo "$CONFIG" | jq -r ".test_targets[$i].name")")
            done
        else
            # 根据检测到的架构选择测试目标
            local count=$(echo "$CONFIG" | jq '.test_targets | length')
            for ((i=0; i<count; i++)); do
                local name=$(echo "$CONFIG" | jq -r ".test_targets[$i].name")
                local target_arch=$(echo "$CONFIG" | jq -r ".test_targets[$i].arch")

                # 检查目标架构是否在检测到的架构列表中
                for arch in $archs; do
                    if [ "$target_arch" == "$arch" ]; then
                        targets+=("$name")
                        break
                    fi
                done
            done
        fi

        if [ ${#targets[@]} -eq 0 ]; then
            log_warn "未找到匹配的测试目标，运行所有测试"
            local count=$(echo "$CONFIG" | jq '.test_targets | length')
            for ((i=0; i<count; i++)); do
                targets+=("$(echo "$CONFIG" | jq -r ".test_targets[$i].name")")
            done
        fi
    elif [ "$TEST_TARGET" == "all" ]; then
        # 从配置获取所有目标
        local count=$(echo "$CONFIG" | jq '.test_targets | length')
        for ((i=0; i<count; i++)); do
            targets+=("$(echo "$CONFIG" | jq -r ".test_targets[$i].name")")
        done
    elif [[ "$TEST_TARGET" == axvisor-qemu ]]; then
        # 运行所有 axvisor QEMU 测试
        local count=$(echo "$CONFIG" | jq '.test_targets | length')
        for ((i=0; i<count; i++)); do
            local name=$(echo "$CONFIG" | jq -r ".test_targets[$i].name")
            if [[ "$name" == axvisor-qemu-* ]]; then
                targets+=("$name")
            fi
        done
    elif [[ "$TEST_TARGET" == axvisor-board ]]; then
        # 运行所有 axvisor 开发板测试
        local count=$(echo "$CONFIG" | jq '.test_targets | length')
        for ((i=0; i<count; i++)); do
            local name=$(echo "$CONFIG" | jq -r ".test_targets[$i].name")
            if [[ "$name" == axvisor-board-* ]]; then
                targets+=("$name")
            fi
        done
    elif [[ "$TEST_TARGET" == starry ]]; then
        # 运行所有 starry 测试
        local count=$(echo "$CONFIG" | jq '.test_targets | length')
        for ((i=0; i<count; i++)); do
            local name=$(echo "$CONFIG" | jq -r ".test_targets[$i].name")
            if [[ "$name" == starry-* ]]; then
                targets+=("$name")
            fi
        done
    else
        # 具体目标名称
        targets+=("$TEST_TARGET")
    fi

    echo "${targets[@]}"
}

# 检查组件是否被目标项目使用（从 Cargo.lock 中检索）
# 返回 0 表示使用，1 表示未使用
check_component_used() {
    local target_name=$1
    local test_dir=$2
    
    # 如果不是 axvisor 或 starry 相关的测试，直接返回使用
    if [[ "$target_name" != axvisor-* ]] && [[ "$target_name" != starry-* ]]; then
        return 0
    fi
    
    local cargo_lock="$test_dir/Cargo.lock"
    
    # 如果 Cargo.lock 不存在，尝试从 Cargo.toml 检查
    if [ ! -f "$cargo_lock" ]; then
        local cargo_toml="$test_dir/Cargo.toml"
        if [ ! -f "$cargo_toml" ]; then
            log_warn "  未找到 Cargo.toml 或 Cargo.lock，无法检查依赖关系"
            return 0
        fi
        
        # 从 Cargo.toml 检查是否有该组件的依赖
        if grep -q "^$COMPONENT_CRATE\s*=" "$cargo_toml" 2>/dev/null; then
            log_debug "  在 Cargo.toml 中找到组件: $COMPONENT_CRATE"
            return 0
        fi
        
        # 检查 workspace members 是否可能包含该组件
        if grep -q "^$COMPONENT_CRATE\s*=" "$test_dir"/*/Cargo.toml 2>/dev/null; then
            log_debug "  在 workspace member 中找到组件: $COMPONENT_CRATE"
            return 0
        fi
        
        return 1
    fi
    
    # 从 Cargo.lock 中检查组件
    # Cargo.lock 格式：[[package]] name = "crate-name"
    if grep -A 1 '^\[\[package\]\]' "$cargo_lock" 2>/dev/null | grep -q "name = \"$COMPONENT_CRATE\""; then
        log_debug "  在 Cargo.lock 中找到组件: $COMPONENT_CRATE"
        return 0
    fi
    
    # 如果直接没找到，尝试从 Cargo.toml 再确认一下（可能是间接依赖）
    local cargo_toml="$test_dir/Cargo.toml"
    if [ -f "$cargo_toml" ] && grep -q "^$COMPONENT_CRATE\s*=" "$cargo_toml" 2>/dev/null; then
        log_debug "  在 Cargo.toml 中找到组件: $COMPONENT_CRATE"
        return 0
    fi
    
    return 1
}

# 检查并关闭占用端口5555的程序
kill_port_5555_processes() {
    local pids=$(sudo lsof -ti :5555 2>/dev/null)
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            log_debug "    关闭进程: PID=$pid"
            sudo kill -9 $pid 2>/dev/null || true
        done
        # 等待端口释放
        sleep 1
    fi
}

# 运行单个测试目标
run_test_target() {
    local target_name=$1
    local current_index=${2:-0}
    local total_count=${3:-1}
    local log_file="$OUTPUT_DIR/logs/${target_name}_$(date +%Y%m%d_%H%M%S).log"
    local status_file="$OUTPUT_DIR/${target_name}.status"
    
    if [ $total_count -gt 1 ]; then
        log "[$current_index/$total_count] 测试目标: $target_name"
    else
        log "测试目标: $target_name"
    fi
    
    # 在测试开始前检查并关闭端口5555
    kill_port_5555_processes
    
    # 获取目标配置
    local target_config=$(echo "$CONFIG" | jq -e ".test_targets[] | select(.name == \"$target_name\")")
    if [ -z "$target_config" ]; then
        log_error "未找到测试目标配置: $target_name"
        echo "failed" > "$status_file"
        return 1
    fi
    
    local repo_url=$(echo "$target_config" | jq -r '.repo.url')
    local repo_branch=$(echo "$target_config" | jq -r '.repo.branch // "main"')
    
    # 如果指定了 --branch 参数，则使用指定的分支
    if [ -n "$GIT_BRANCH" ]; then
        repo_branch="$GIT_BRANCH"
        log "  使用指定分支: $repo_branch"
    fi
    local test_type=$(echo "$target_config" | jq -r '.type // "qemu"')
    local build_cmd=$(echo "$target_config" | jq -r '.build.command')
    local timeout_min=$(echo "$target_config" | jq -r '.build.timeout_minutes // 15')
    
    log_debug "  仓库: $repo_url ($repo_branch)"
    log_debug "  类型: $test_type"
    log_debug "  构建: $build_cmd"
    log_debug "  超时: ${timeout_min}分钟"
    
    # 测试目录
    local test_dir="$OUTPUT_DIR/repos/$target_name"
    
    # 克隆或更新仓库
    if [ ! -d "$test_dir" ]; then
        # 判断是否为 axvisor 目标，且未使用 --git 选项时，使用 cargo clone 从 crates.io 下载
        if [[ "$target_name" == axvisor-* ]] && [ "$USE_GIT" == false ]; then
            log "  从 crates.io 下载 axvisor..."
            if [ "$DRY_RUN" == true ]; then
                echo "[DRY-RUN] cargo clone axvisor -- $test_dir"
            else
                if ! cargo clone axvisor -- "$test_dir" >> "$log_file" 2>&1; then
                    log_error "  下载 axvisor 失败"
                    echo "failed" > "$status_file"
                    return 1
                fi
            fi
        else
            log "  克隆仓库..."
            if [ "$DRY_RUN" == true ]; then
                echo "[DRY-RUN] git clone --depth 1 -b $repo_branch $repo_url $test_dir"
            else
                if ! git clone --depth 1 -b $repo_branch "$repo_url" "$test_dir" >> "$log_file" 2>&1; then
                    log_error "  克隆仓库失败: $repo_url"
                    echo "failed" > "$status_file"
                    return 1
                fi
                # 初始化子模块
                if [ -f "$test_dir/.gitmodules" ]; then
                    log "  初始化子模块..."
                    (cd "$test_dir" && git submodule update --init --recursive) >> "$log_file" 2>&1 || true
                fi
            fi
        fi
    else
        log "  更新仓库..."
        if [ "$DRY_RUN" != true ]; then
            if [[ "$target_name" == axvisor-* ]] && [ "$USE_GIT" == false ]; then
                # axvisor 使用 cargo clone，不进行 git pull
                log "  axvisor 从 crates.io 下载，跳过更新"
            else
                (cd "$test_dir" && git pull) >> "$log_file" 2>&1 || true
            fi
        fi
    fi
    
    # 确保仓库目录存在 (dry-run 模式下跳过)
    if [ "$DRY_RUN" != true ] && [ ! -d "$test_dir" ]; then
        log_error "  仓库目录不存在: $test_dir"
        echo "failed" > "$status_file"
        return 1
    fi
    
    # dry-run 模式下跳过后续操作
    if [ "$DRY_RUN" == true ]; then
        log "  DRY RUN: 跳过 patch、构建和测试"
        echo "skipped" > "$status_file"
        return 2
    fi
    
    # 检查当前组件是否被目标项目使用（针对 axvisor/starry 测试）
    if [[ "$target_name" == axvisor-* ]] || [[ "$target_name" == starry-* ]]; then
        if ! check_component_used "$target_name" "$test_dir"; then
            log_warn "  跳过测试: 当前组件 '$COMPONENT_CRATE' 未在 $target_name 的依赖中使用"
            echo "skipped" > "$status_file"
            return 2
        fi
    fi
    
    # 应用 patch - 与 CI 逻辑保持一致
    # 优先级: 目标配置 > 全局配置 > 默认值
    local patch_section=$(echo "$target_config" | jq -r '.patch.section // empty')
    [ -z "$patch_section" ] && patch_section=$(echo "$CONFIG" | jq -r '.patch.section // "crates-io"')
    
    local patch_path=$(echo "$target_config" | jq -r '.patch.path_template // empty')
    [ -z "$patch_path" ] && patch_path=$(echo "$CONFIG" | jq -r '.patch.path_template // "../component"')
    
    # 转换为绝对路径
    if [[ "$patch_path" == ".."* ]]; then
        # 尝试从 test_dir 解析相对路径
        local resolved_path="$test_dir/$patch_path"
        if [ -d "$resolved_path" ]; then
            patch_path="$(cd "$resolved_path" && pwd)"
        else
            # 如果相对路径解析失败，直接使用组件目录的绝对路径
            patch_path="$COMPONENT_DIR"
        fi
    fi
    
    log "  应用组件 patch (section: $patch_section, path: $patch_path)..."
    if [ "$DRY_RUN" == true ]; then
        echo "[DRY-RUN] 添加 patch 到 $test_dir/Cargo.toml"
    else
        cd "$test_dir"
        
        # 检查是否已添加该组件的 patch（只在 [patch.*] section 中检查）
        # 使用 grep 检查 patch section 中是否已有该组件
        if grep -E "^\[patch\." Cargo.toml >/dev/null 2>&1 && \
           grep -A 100 "^\[patch\." Cargo.toml | grep -q "^$COMPONENT_CRATE\s*="; then
            log "  组件 $COMPONENT_CRATE 已在 patch 中"
        else
            # 检查是否已存在 [patch.$patch_section] section
            if grep -q "^\[patch\.$patch_section\]" Cargo.toml 2>/dev/null; then
                # 在现有的 section 后添加
                # 使用 sed 在匹配行后插入
                sed -i "/^\[patch\.$patch_section\]/a $COMPONENT_CRATE = { path = \"$patch_path\" }" Cargo.toml
                log_debug "已在现有 patch section 中添加组件"
            else
                # 创建新的 section
                cat >> Cargo.toml << EOF

[patch.$patch_section]
$COMPONENT_CRATE = { path = "$patch_path" }
EOF
                log_debug "已创建新的 patch section 并添加组件"
            fi
        fi
    fi
    
    # 执行构建
    if [ -n "$build_cmd" ]; then
        log "  构建... ($build_cmd, timeout: ${timeout_min}m)"
        
        if [ "$DRY_RUN" == true ]; then
            echo "[DRY-RUN] cd $test_dir && timeout ${timeout_min}m $build_cmd"
        else
            cd "$test_dir"
            # 为 starry 测试准备构建命令
            local actual_build_cmd="$build_cmd"
            if [[ "$target_name" == starry-* ]]; then
                local arch=$(echo "$target_config" | jq -r '.arch')
                log "  构建架构: $arch"
                # 将 ARCH 作为 make 参数传递，而不是环境变量
                actual_build_cmd="$build_cmd ARCH=$arch"
            fi
            
            if timeout "${timeout_min}m" sh -c "$actual_build_cmd" >> "$log_file" 2>&1; then

                # 为 starry 测试准备 rootfs
                if [[ "$target_name" == starry-* ]]; then
                    log "  准备 rootfs..."
                    local arch=$(echo "$target_config" | jq -r '.arch')
                    # 将 ARCH 作为 make 参数传递，而不是环境变量
                    # rootfs 准备使用独立的超时时间（1分钟）
                    if timeout 1m sh -c "make rootfs ARCH=$arch" >> "$log_file" 2>&1; then
                        log "  Rootfs 准备完成"
                    else
                        local rootfs_exit_code=$?
                        if [ $rootfs_exit_code -eq 124 ]; then
                            log_error "  Rootfs 准备超时，请检查网络环境"
                        else
                            log_error "  Rootfs 准备失败（退出码: $rootfs_exit_code）: $target_name"
                        fi
                        echo "failed" > "$status_file"
                        cd "$COMPONENT_DIR"
                        return 1
                    fi
                fi
            else
                local exit_code=$?
                if [ $exit_code -eq 124 ]; then
                    log_error "  构建超时: $target_name"
                else
                    log_error "  构建失败: $target_name (退出码: $exit_code)"
                fi
                echo "failed" > "$status_file"
                cd "$COMPONENT_DIR"
                return 1
            fi
        fi
    fi
    
    # 执行测试（如果有测试配置）
    local has_test=$(echo "$target_config" | jq 'has("test")')
    if [ "$has_test" == "true" ]; then
        local test_cmd=$(echo "$target_config" | jq -r '.test.command')
        local test_timeout=$(echo "$target_config" | jq -r '.test.timeout_minutes // 30')
        
        log "  运行测试... ($test_cmd, timeout: ${test_timeout}m)"
        
        # Board 测试前准备
        if [ "$test_type" == "board" ]; then
            # 确保安装 ostool
            if ! command -v ostool &> /dev/null; then
                log "  安装 ostool..."
                cargo +stable install ostool --version ^0.8
            fi

            # 创建 TFTP 目录
            local bin_dir=$(echo "$target_config" | jq -r '.test.bin_dir // "/tmp/tftp"')
            sudo mkdir -p "$bin_dir"
            sudo chmod 777 "$bin_dir"
            log "  TFTP 目录已准备: $bin_dir"
            
            # 下载镜像和配置（类似 QEMU 测试）
            local vmconfigs=$(echo "$target_config" | jq -r '.test.vmconfigs')
            local vmimage_name=$(echo "$target_config" | jq -r '.test.vmimage_name // empty')
            
            if [ -n "$vmimage_name" ]; then
                log "  下载测试镜像..."
                
                # 创建镜像目录
                local IMAGE_DIR="/tmp/.axvisor-images"
                sudo mkdir -p "$IMAGE_DIR"
                sudo chmod 777 "$IMAGE_DIR"
                
                # 检查并下载镜像
                IFS=',' read -ra CONFIGS <<< "$vmconfigs"
                IFS=',' read -ra IMAGES <<< "$vmimage_name"
                
                for i in "${!CONFIGS[@]}"; do
                    img="${IMAGES[$i]}"
                    img=$(echo "$img" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    config="${CONFIGS[$i]}"
                    config=$(echo "$config" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    
                    # 检查镜像是否存在
                    local img_path="${IMAGE_DIR}/${img}"
                    if [ -d "$img_path" ]; then
                        log "  镜像已存在: $img_path"
                    else
                        log "  镜像不存在，开始下载: $img"
                        if [ -f "$test_dir/$config" ]; then
                            cd "$test_dir"
                            if cargo xtask image download $img >> "$log_file" 2>&1; then
                                log_success "  镜像下载成功: $img"
                            else
                                log_error "  镜像下载失败: $img"
                                echo "failed" > "$status_file"
                                cd "$COMPONENT_DIR"
                                return 1
                            fi
                        else
                            log_warn "  配置文件不存在: $config"
                        fi
                    fi
                    
                    # 更新配置文件（仅在非 --fs 模式下）
                    if [ "$USE_FS_MODE" == true ]; then
                        log "  --fs 模式: 跳过配置文件修改"
                    elif [ -f "$test_dir/$config" ]; then
                        cd "$test_dir"
                        
                        # 获取 image_location
                        local image_location=$(sed -n 's/^image_location[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$config")
                        local board_name=$(echo "$target_config" | jq -r '.board')
                        
                        # Board 测试的内核文件名（与 board 同名，例如 phytiumpi）
                        local kernel_name="${board_name}"
                        
                        case "$image_location" in
                        "fs")
                            log "  将配置从文件系统模式改为内存模式"
                            # 修改 image_location 为 memory
                            sed -i 's|^image_location[[:space:]]*=.*|image_location = "memory"|' "$config"
                            # 更新 kernel_path 指向镜像目录中的内核文件
                            sed -i 's|^kernel_path[[:space:]]*=.*|kernel_path = "'"${IMAGE_DIR}"'/'"$img"'/'"$kernel_name"'"|' "$config"
                            log "  已更新 kernel_path: ${IMAGE_DIR}/${img}/${kernel_name}"
                            ;;
                        "memory")
                            log "  内存存储模式 - 更新 kernel_path"
                            sed -i 's|^kernel_path[[:space:]]*=.*|kernel_path = "'"${IMAGE_DIR}"'/'"$img"'/'"$kernel_name"'"|' "$config"
                            log "  已更新 kernel_path: ${IMAGE_DIR}/${img}/${kernel_name}"
                            ;;
                        *)
                            log "  未知的 image_location: $image_location，修改为 memory"
                            sed -i 's|^image_location[[:space:]]*=.*|image_location = "memory"|' "$config"
                            sed -i 's|^kernel_path[[:space:]]*=.*|kernel_path = "'"${IMAGE_DIR}"'/'"$img"'/'"$kernel_name"'"|' "$config"
                            log "  已更新 kernel_path: ${IMAGE_DIR}/${img}/${kernel_name}"
                            ;;
                        esac
                    else
                        log_warn "  配置文件不存在: $config"
                    fi
                done
                cd "$COMPONENT_DIR"
            fi
        fi
        
        # 下载镜像和配置（仅适用于 axvisor QEMU 测试）
        if [[ "$target_name" == axvisor-qemu-* ]]; then
            local arch=$(echo "$target_config" | jq -r '.arch')
            local vmconfigs=$(echo "$target_config" | jq -r '.test.vmconfigs')
            local vmimage_name=$(echo "$target_config" | jq -r '.test.vmimage_name // empty')
            
            if [ -n "$vmimage_name" ]; then
                log "  下载测试镜像..."
                
                # 创建镜像目录
                local IMAGE_DIR="/tmp/.axvisor-images"
                sudo mkdir -p "$IMAGE_DIR"
                sudo chmod 777 "$IMAGE_DIR"
                
                # 安装 ostool（如果尚未安装）
                if ! command -v ostool &> /dev/null; then
                    log "  安装 ostool..."
                    cargo +stable install ostool --version ^0.8
                fi
                
                # 检查并下载镜像
                IFS=',' read -ra CONFIGS <<< "$vmconfigs"
                IFS=',' read -ra IMAGES <<< "$vmimage_name"
                
                for i in "${!CONFIGS[@]}"; do
                    img="${IMAGES[$i]}"
                    img=$(echo "$img" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    config="${CONFIGS[$i]}"
                    config=$(echo "$config" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    
                    # 检查镜像是否存在
                    local img_path="${IMAGE_DIR}/${img}"
                    if [ -d "$img_path" ]; then
                        log "  镜像已存在: $img_path"
                    else
                        log "  镜像不存在，开始下载: $img"
                        if [ -f "$test_dir/$config" ]; then
                            cd "$test_dir"
                            if cargo xtask image download $img >> "$log_file" 2>&1; then
                                log_success "  镜像下载成功: $img"
                            else
                                log_error "  镜像下载失败: $img"
                                echo "failed" > "$status_file"
                                cd "$COMPONENT_DIR"
                                return 1
                            fi
                        else
                            log_warn "  配置文件不存在: $config"
                        fi
                    fi
                    
                    if [ -f "$test_dir/$config" ]; then
                        cd "$test_dir"
                        
                        # 获取 image_location
                        local image_location=$(sed -n 's/^image_location[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$config")
                        local img_name="qemu-$arch"
                        
                        case "$image_location" in
                        "fs")
                            log "  文件系统存储模式 - 无需更新配置"
                            ;;
                        "memory")
                            sed -i 's|^kernel_path[[:space:]]*=.*|kernel_path = "'"${IMAGE_DIR}"'/'"$img"'/'"$img_name"'"|' "$config"
                            log "  内存存储模式 - 已更新 kernel_path"
                            ;;
                        *)
                            log "  未知的 image_location: $image_location"
                            ;;
                        esac
                        
                        # 检查并处理 rootfs.img
                        local ROOTFS_IMG_PATH="${IMAGE_DIR}/$img/rootfs.img"
                        local qemu_config="$test_dir/$(echo "$target_config" | jq -r '.test.qemu_config')"
                        
                        if [ -f "${ROOTFS_IMG_PATH}" ]; then
                            log "  找到 rootfs.img，更新 $qemu_config"
                            sed -i 's|file=${workspaceFolder}/tmp/rootfs.img|file='"${ROOTFS_IMG_PATH}"'|' "$qemu_config"
                            log "  Rootfs 配置完成"
                        else
                            log "  未找到 rootfs.img，移除 rootfs 设备配置"
                            sed -i '/-device/,/virtio-blk-device,drive=disk0/d' "$qemu_config"
                            sed -i '/-drive/,/id=disk0,if=none,format=raw,file=${workspaceFolder}\/tmp\/rootfs.img/d' "$qemu_config"
                            sed -i 's/root=\/dev\/vda rw //' "$qemu_config"
                            log "  Rootfs 设备配置已移除"
                        fi
                    else
                        log_warn "  配置文件不存在: $config"
                    fi
                done
                cd "$COMPONENT_DIR"
            fi
        fi
        
        # 准备测试命令
        local full_test_cmd=""
        if [[ "$target_name" == axvisor-qemu-* ]]; then
            # Axvisor QEMU 测试
            local build_config=$(echo "$target_config" | jq -r '.test.build_config')
            local qemu_config=$(echo "$target_config" | jq -r '.test.qemu_config')
            local vmconfigs=$(echo "$target_config" | jq -r '.test.vmconfigs')
            full_test_cmd="$test_cmd --build-config $build_config --qemu-config $qemu_config --vmconfigs $vmconfigs"
        elif [[ "$target_name" == axvisor-board-* ]]; then
            # Axvisor Board 测试
            local build_config=$(echo "$target_config" | jq -r '.test.build_config')
            local uboot_config=$(echo "$target_config" | jq -r '.test.uboot_config')
            local vmconfigs=$(echo "$target_config" | jq -r '.test.vmconfigs')
            local bin_dir=$(echo "$target_config" | jq -r '.test.bin_dir // "/tmp/tftp"')

            cd "$test_dir"

            # 步骤 1: 执行 defconfig 生成 .build.toml
            log "  生成构建配置..."
            local board_name=$(echo "$target_config" | jq -r '.board')

            # 获取客户机配置文件列表
            # vmconfigs 是逗号分隔的列表，例如: "configs/vms/arceos-aarch64-e2000-smp1.toml"
            # 需要解析这些配置文件路径并配置到 vm_configs
            local vm_configs_json="["
            local vm_configs=$(echo "$target_config" | jq -r '.test.vmconfigs')
            IFS=',' read -ra CONFIGS <<< "$vmconfigs"
            for i in "${!CONFIGS[@]}"; do
                config="${CONFIGS[$i]}"
                config=$(echo "$config" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                if [ $i -gt 0 ]; then
                    vm_configs_json+=", "
                fi
                vm_configs_json+='"'"$config"'"'
            done
            vm_configs_json+="]"

            log "  执行 cargo xtask defconfig $board_name..."
            if cargo xtask defconfig "$board_name" >> "$log_file" 2>&1; then
                log_success "  Defconfig 成功"
            else
                log_error "  Defconfig 失败"
                echo "failed" > "$status_file"
                cd "$COMPONENT_DIR"
                return 1
            fi

            # 步骤 2: 修改 .build.toml 文件
            log "  更新 .build.toml 配置..."
            local build_toml=".build.toml"

            if [ -f "$build_toml" ]; then
                if [ "$USE_FS_MODE" == true ]; then
                    local fs_vm_configs=""
                    case "$target_name" in
                        axvisor-board-phytiumpi-arceos)
                            fs_vm_configs='["configs/vms/arceos-aarch64-e2000-smp1.toml"]'
                            ;;
                        axvisor-board-phytiumpi-linux)
                            fs_vm_configs='["configs/vms/linux-aarch64-e2000-smp1.toml"]'
                            ;;
                        axvisor-board-roc-rk3568-pc-arceos)
                            fs_vm_configs='["configs/vms/arceos-aarch64-rk3568-smp1.toml"]'
                            ;;
                        axvisor-board-roc-rk3568-pc-linux)
                            fs_vm_configs='["configs/vms/linux-aarch64-rk3568-smp1.toml"]'
                            ;;
                        *)
                            log_warn "  未知目标: $target_name，使用默认 vm_configs"
                            fs_vm_configs="$vm_configs_json"
                            ;;
                    esac

                    # 仅替换 vm_configs，保留 features
                    awk -v vm_configs="$fs_vm_configs" '
                        /^vm_configs = \[/ { in_vm=1; next }
                        in_vm { if(/^\]/) { in_vm=0 } next }
                        /^log = / { print $0 "\nvm_configs = " vm_configs; next }
                        { print }
                    ' "$build_toml" > "$build_toml.tmp" && mv "$build_toml.tmp" "$build_toml"

                    log_success "  .build.toml 更新完成 (--fs 模式)"
                    log_debug "    - vm_configs: $fs_vm_configs"
                else
                    # 非 --fs 模式: 修改 features 和 vm_configs
                    awk -v vm_configs="$vm_configs_json" '
                        /^features = \[/ { in_features=1; print "features = ["; print "    # \"ept-level-4\","; print "    \"dyn-plat\","; print "    \"axstd/bus-mmio\","; print "]"; next }
                        in_features { if(/^\]/) { in_features=0 } next }
                        /^vm_configs = \[/ { in_vm=1; next }
                        in_vm { if(/^\]/) { in_vm=0 } next }
                        /^log = / { print $0 "\nvm_configs = " vm_configs; next }
                        { print }
                    ' "$build_toml" > "$build_toml.tmp" && mv "$build_toml.tmp" "$build_toml"

                    log_success "  .build.toml 更新完成"
                    log_debug "    - Features 已更新"
                    log_debug "    - vm_configs: $vm_configs_json"
                fi
            else
                log_error "  未找到 .build.toml 文件"
                echo "failed" > "$status_file"
                cd "$COMPONENT_DIR"
                return 1
            fi

            # 步骤 3: 检查 .uboot.toml 是否存在，不存在则从配置文件读取或提示用户输入
            log "  检查 U-Boot 配置..."
            local uboot_config_file=".uboot.toml"
            local uboot_json_file="$COMPONENT_DIR/.uboot.json"

            if [ ! -f "$uboot_config_file" ]; then
                local serial_input=""
                local baud_rate_input=""
                local dtb_file_input=""
                local board_name=$(echo "$target_config" | jq -r '.board')

                # 尝试从 .uboot.json 读取配置
                if [ -f "$uboot_json_file" ]; then
                    log "  从 .uboot.json 读取 $board_name 的配置..."
                    
                    # 检查配置文件中是否有该 board 的配置
                    local board_config=$(jq -e ".boards[\"$board_name\"]" "$uboot_json_file" 2>/dev/null)
                    if [ $? -eq 0 ] && [ -n "$board_config" ]; then
                        serial_input=$(echo "$board_config" | jq -r '.serial // empty')
                        baud_rate_input=$(echo "$board_config" | jq -r '.baud_rate // empty')
                        dtb_file_input=$(echo "$board_config" | jq -r '.dtb_file // empty')
                        
                        if [ -n "$serial_input" ] && [ -n "$baud_rate_input" ] && [ -n "$dtb_file_input" ]; then
                            log "  从配置文件读取到:"
                            log "  - 串口: $serial_input"
                            log "  - 波特率: $baud_rate_input"
                            log "  - DTB文件: $dtb_file_input"
                        else
                            log_warn "  .uboot.json 中 $board_name 的配置不完整，将使用交互式输入"
                            serial_input=""
                            baud_rate_input=""
                            dtb_file_input=""
                        fi
                    else
                        log_warn "  .uboot.json 中未找到 $board_name 的配置，将使用交互式输入"
                    fi
                else
                    log "  未找到 .uboot.json 配置文件 ($uboot_json_file)"
                fi

                # 如果从配置文件读取失败，则使用交互式输入
                if [ -z "$serial_input" ] || [ -z "$baud_rate_input" ] || [ -z "$dtb_file_input" ]; then
                    log ""
                    log "  ======== 配置 U-Boot 参数 ======== "
                    log ""

                    # 提示用户输入 serial
                    echo -e "${CYAN}请输入串口设备路径 (例如: /dev/ttyUSB0):${NC}"
                    read -p "> " serial_input
                    serial_input="${serial_input:-/dev/ttyUSB0}"

                    # 提示用户输入 baud_rate
                    echo ""
                    echo -e "${CYAN}请输入波特率 (例如: 115200):${NC}"
                    read -p "> " baud_rate_input
                    baud_rate_input="${baud_rate_input:-115200}"

                    # 提示用户输入 dtb_file
                    echo ""
                    echo -e "${CYAN}请输入 DTB 文件路径 (例如: board/orangepi-5-plus.dtb):${NC}"
                    read -p "> " dtb_file_input
                    dtb_file_input="${dtb_file_input:-board/orangepi-5-plus.dtb}"
                    
                    log ""
                fi

                # 生成 .uboot.toml 文件
                cat > "$uboot_config_file" << EOF
serial = "$serial_input"
baud_rate = "$baud_rate_input"
success_regex = []
fail_regex = []
dtb_file = "$dtb_file_input"
EOF

                log "  U-Boot 配置已保存到: $uboot_config_file"
                log ""
            else
                log "  使用已存在的配置文件: $uboot_config_file"
            fi

            # 步骤 4: 执行 cargo xtask uboot
            full_test_cmd="$test_cmd"
        elif [[ "$target_name" == starry-* ]]; then
            # Starry 测试
            local arch=$(echo "$target_config" | jq -r '.arch')
            full_test_cmd="make ARCH=$arch run"
        fi

        if [ "$DRY_RUN" == true ]; then
            echo "[DRY-RUN] cd $test_dir && timeout ${test_timeout}m $full_test_cmd"
        else
            cd "$test_dir"
            export RUST_LOG=debug

            # 使用成功检测函数运行测试
            # 对于 board 测试，传入 board_name 和 test_dir 用于电源控制和资源清理
            if [ "$test_type" == "board" ]; then
                local board_name=$(echo "$target_config" | jq -r '.board // empty')
                run_with_success_detection "$full_test_cmd" "${test_timeout}" "$log_file" "$board_name" "$test_dir"
            else
                run_with_success_detection "$full_test_cmd" "${test_timeout}" "$log_file"
            fi
            local exit_code=$?

            if [ $exit_code -eq 0 ]; then
                log_success "  测试成功: $target_name"
                echo "passed" > "$status_file"
                cd "$COMPONENT_DIR"
                return 0
            elif [ $exit_code -eq 124 ]; then
                log_error "  测试超时（未检测到成功标识符）: $target_name"
                echo "failed" > "$status_file"
                cd "$COMPONENT_DIR"
                return 1
            else
                log_error "  测试失败（退出码: $exit_code）: $target_name"
                echo "failed" > "$status_file"
                cd "$COMPONENT_DIR"
                return 1
            fi
        fi
    else
        # 没有测试配置，仅构建成功就算通过
        log_success "  仅构建，无测试: $target_name"
        echo "passed" > "$status_file"
        cd "$COMPONENT_DIR"
        return 0
    fi
}

# 运行所有测试
run_all_tests() {
    local targets=$(get_test_targets)
    local failed=0
    local passed=0
    local skipped=0
    local pids=()
    local target_array=()
    
    # 转换为数组
    read -ra target_array <<< "$targets"
    local total_count=${#target_array[@]}

    log "测试目标: ${target_array[*]}"
    echo ""

    local force_sequential=false
    if [[ "$TEST_TARGET" == "all" ]] || [[ "$TEST_TARGET" == "starry" ]] || [[ "$TEST_TARGET" == "axvisor-board" ]]; then
        force_sequential=true
    fi

    if [ "$PARALLEL" == true ] && [ $total_count -gt 1 ] && [ "$force_sequential" == false ]; then
        # 并行执行
        for i in "${!target_array[@]}"; do
            local target="${target_array[$i]}"
            run_test_target "$target" $((i+1)) $total_count &
            pids+=($!)
        done
        
        # 等待所有任务完成
        for i in "${!pids[@]}"; do
            if ! wait ${pids[$i]}; then
                ((failed++))
            else
                ((passed++))
            fi
        done
    else
        # 顺序执行
        for i in "${!target_array[@]}"; do
            local target="${target_array[$i]}"
            run_test_target "$target" $((i+1)) $total_count
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                ((passed++))
            elif [ $exit_code -eq 2 ]; then
                ((skipped++))
            else
                ((failed++))
            fi
        done
    fi
    
    echo ""
    log "测试结果:"
    echo "  - 通过: $passed"
    echo "  - 失败: $failed"
    echo "  - 跳过: $skipped"
    
    # 生成报告
    generate_report "$passed" "$failed" "$skipped"
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# 生成报告
generate_report() {
    local passed=$1
    local failed=$2
    local skipped=$3
    local report_file="$OUTPUT_DIR/report.md"
    
    cat > "$report_file" << EOF
# 测试报告

**组件**: $COMPONENT_NAME 
**时间**: $(date '+%Y-%m-%d %H:%M:%S')  
**配置**: $CONFIG_FILE

## 结果汇总

| 状态 | 数量 |
|------|------|
| ✅ 通过 | $passed |
| ❌ 失败 | $failed |
| ⏭️ 跳过 | $skipped |

## 详细结果

EOF
    
    for status_file in "$OUTPUT_DIR"/*.status; do
        if [ -f "$status_file" ]; then
            local name=$(basename "$status_file" .status)
            local status=$(cat "$status_file")
            if [ "$status" == "passed" ]; then
                echo "- $name: ✅ 通过" >> "$report_file"
            elif [ "$status" == "skipped" ]; then
                echo "- $name: ⏭️ 跳过 (需要硬件)" >> "$report_file"
            else
                echo "- $name: ❌ 失败" >> "$report_file"
            fi
        fi
    done
    
    log_debug "报告已生成: $report_file"
}

# 清理
cleanup() {
    if [ "$CLEANUP" == true ] && [ "$DRY_RUN" != true ]; then
        log_debug "清理临时文件..."
        
        # 恢复 Cargo.toml
        for test_dir in "$OUTPUT_DIR/repos"/*; do
            if [ -d "$test_dir" ]; then
                (cd "$test_dir" && git checkout Cargo.toml 2>/dev/null) || true
            fi
        done
    fi
}

# 主函数
main() {
    parse_args "$@"

    # 处理 --clean 命令
    if [ "$CLEAN_RESULTS" == true ]; then
        if [ -z "$OUTPUT_DIR" ]; then
            # 如果未指定输出目录，使用默认目录
            if [ -z "$COMPONENT_DIR" ]; then
                COMPONENT_DIR="$(pwd)"
            fi
            OUTPUT_DIR="$COMPONENT_DIR/test-results"
        fi
        if [ -d "$OUTPUT_DIR" ]; then
            log "清理测试目录: $OUTPUT_DIR"
            sudo rm -rf "$OUTPUT_DIR"
            log_success "清理完成"
        else
            log "测试目录不存在: $OUTPUT_DIR"
        fi
        exit 0
    fi

    # 处理 --list-json: 输出所有测试目标的 JSON 数组 (用于 CI matrix)
    # 必须在任何日志输出之前处理
    if [ "$LIST_JSON" == true ]; then
        load_config >/dev/null 2>&1
        local targets=$(echo "$CONFIG" | jq -c '[.test_targets[].name]')
        echo "$targets"
        exit 0
    fi

    # 处理 --list-auto: 输出自动检测的测试目标 (用于 CI matrix)
    if [ "$LIST_AUTO" == true ]; then
        load_config >/dev/null 2>&1
        local targets=$(get_test_targets)
        echo "$targets" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s -c
        exit 0
    fi

    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Hypervisor Test Framework${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""

    check_dependencies
    load_config

    log "配置加载完成"
    log "组件: $COMPONENT_NAME ($COMPONENT_CRATE)"

    # 处理 list 命令
    if [ "$TEST_TARGET" == "list" ]; then
        echo ""
        echo "所有可用的测试目标:"
        echo ""
        local count=$(echo "$CONFIG" | jq '.test_targets | length')
        for ((i=0; i<count; i++)); do
            local name=$(echo "$CONFIG" | jq -r ".test_targets[$i].name")
            echo "  $name"
        done
        echo ""
        exit 0
    fi

    setup_output

    log "输出目录: $OUTPUT_DIR"

    if [ "$DRY_RUN" == true ]; then
        log_warn "DRY RUN 模式 - 不会执行实际操作"
    fi

    # 临时禁用 set -e 以捕获 run_all_tests 的返回值
    set +e
    run_all_tests
    local result=$?
    set -e

    cleanup

    echo ""
    if [ $result -eq 0 ]; then
        log_success "所有测试通过!"
    elif [ $result -eq 2 ]; then
        log_warn "部分测试被跳过"
    else
        log_error "部分测试失败"
    fi

    exit $result
}

# 捕获信号
trap cleanup EXIT INT TERM

main "$@"
