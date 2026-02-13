#!/bin/bash
#
# arm_vcpu 本地测试脚本
# 此脚本会下载并调用共享测试框架
#
# 用法:
#   ./scripts/run_tests.sh              # 运行所有测试
#   ./scripts/run_tests.sh -t axvisor   # 仅测试 axvisor
#   ./scripts/run_tests.sh -v           # 详细输出
#

set -e

FRAMEWORK_REPO="https://github.com/arceos-hypervisor/hypervisor-test-framework"
FRAMEWORK_BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="$(dirname "$SCRIPT_DIR")"
FRAMEWORK_CACHE="$HOME/.cache/hypervisor-test-framework"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 下载或更新测试框架
download_framework() {
    log "获取测试框架..."
    
    mkdir -p "$(dirname "$FRAMEWORK_CACHE")"
    
    if [ -d "$FRAMEWORK_CACHE" ]; then
        (cd "$FRAMEWORK_CACHE" && git pull -q 2>/dev/null) || true
    else
        git clone --depth 1 -b "$FRAMEWORK_BRANCH" "$FRAMEWORK_REPO" "$FRAMEWORK_CACHE"
    fi
    
    log_success "测试框架就绪"
}

# 运行测试
run_tests() {
    log "组件目录: $COMPONENT_DIR"
    
    # 调用框架脚本，传递所有参数
    exec "$FRAMEWORK_CACHE/scripts/run_tests.sh" \
        --component-dir "$COMPONENT_DIR" \
        "$@"
}

# 主函数
main() {
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  arm_vcpu 测试${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    
    download_framework
    run_tests "$@"
}

main "$@"
