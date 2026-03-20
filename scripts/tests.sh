#!/bin/bash
#
# Hypervisor Test Framework - 本地测试脚本
# 此脚本可独立运行，也可被各组件调用
#
# 用法:
#   ./test.sh                           # 运行所有测试
#   ./test.sh --target axvisor-qemu     # 仅测试指定目标
#   ./test.sh --config /path/to/.test-config.json
#   ./test.sh --component-dir /path/to/component
#

set -e
set -o pipefail

# 加载所有模块
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/repo.sh"
source "$SCRIPT_DIR/lib/patch.sh"
source "$SCRIPT_DIR/lib/image.sh"
source "$SCRIPT_DIR/lib/qemu.sh"
source "$SCRIPT_DIR/lib/board.sh"
source "$SCRIPT_DIR/lib/runner.sh"
source "$SCRIPT_DIR/lib/report.sh"

# 默认配置
COMPONENT_DIR=""
CONFIG_FILE=""
TEST_TARGET="all"
FILTER_TARGETS=""
FILTER_UNIT_TARGETS=""
FILTER_SUITE=""
VERBOSE=false
CLEANUP=true
DRY_RUN=false
PARALLEL=false
OUTPUT_DIR=""
USE_GIT=false
GIT_BRANCH=""
CLEAN_RESULTS=false
LIST_JSON=false
LIST_AUTO=false
USE_FS_MODE=false
PRINT_OUTPUT=false

# 帮助信息
show_help() {
    cat << 'EOF'
Hypervisor Test Framework - 本地测试脚本

用法:
  test.sh [选项]

选项:
  -c, --component-dir DIR    组件目录 (默认: 当前目录)
  -f, --config FILE          配置文件路径 (可选，默认使用内置测试目标)
  --targets TRIPLE[,TRIPLE,...]  编译目标三元组 (如: aarch64-unknown-none-softfloat)
                             用于集成测试架构过滤，支持前缀匹配
                             优先级: CLI > config.json targets > rust-toolchain.toml 自动检测
  --unit-targets TRIPLE      单元测试目标 (如: aarch64-unknown-none-softfloat)
                             优先级: CLI > config.json unit_test_targets > 跳过单元测试
  --suite NAME[,NAME,...]    测试套件过滤 (如: axvisor-qemu,starry-aarch64)
                             支持精确名称和前缀匹配 (axvisor-qemu 匹配 axvisor-qemu-*)
                             优先级: CLI > config.json test_targets > 全部
  -o, --output DIR           输出目录 (默认: COMPONENT_DIR/test-results)
  -v, --verbose              详细输出
  --no-cleanup               不清理临时文件
  --dry-run                  仅显示将要执行的命令
  --parallel                 并行执行测试 (默认顺序执行)
  --from-git                 从 git 仓库拉取代码 (默认从 crates.io 下载)
  --branch BRANCH            指定 git 分支 (仅与 --from-git 一起使用)
  --clean                    清理测试生成的 test-results 目录
  --list-json                列出所有测试目标 (JSON 格式，用于 CI matrix)
  --list-auto                列出自动检测的测试目标 (JSON 格式)
  --fs                       使用文件系统模式，不修改配置文件
  --print                    打印 U-Boot 和串口输出到命令行
  -h, --help                 显示此帮助

测试模式 (位置参数):
  all                        运行单元测试 + 集成测试 (默认)
  unit                       运行单元测试
  integration                运行集成测试

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
  axvisor-board-x86_64-pc-arceos  测试 axvisor 在 x86_64-pc 开发板上的 ArceOS 镜像
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
  test.sh                                         # 运行全部
  test.sh unit                                    # 仅单元测试
  test.sh integration                             # 仅集成测试
  test.sh integration --targets aarch64-unknown-none-softfloat  # 指定目标
  test.sh integration --suite axvisor-qemu        # 仅 axvisor-qemu 系列
  test.sh all --unit-targets aarch64-unknown-none-softfloat --suite axvisor-qemu
  test.sh --dry-run -v                            # 显示将要执行的命令

EOF
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            all|unit|integration|list)
                TEST_TARGET="$1"
                shift
                ;;
            -c|--component-dir)
                COMPONENT_DIR="$2"
                shift 2
                ;;
            -f|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --targets)
                FILTER_TARGETS="$2"
                shift 2
                ;;
            --unit-targets)
                FILTER_UNIT_TARGETS="$2"
                shift 2
                ;;
            -s|--suite)
                FILTER_SUITE="$2"
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
            --list-json)
                LIST_JSON=true
                shift
                ;;
            --list-auto)
                LIST_AUTO=true
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

# 解析 --targets 为完整 triple 列表和短架构名列表
# 优先级: CLI --targets > config.json targets > rust-toolchain.toml 自动检测
# 设置全局变量:
#   RESOLVED_TRIPLES - 空格分隔的完整 triple (用于 cargo test --target)
#   RESOLVED_ARCHS   - 空格分隔的短架构名 (用于 integration 过滤) 或 "all"
resolve_targets() {
    local targets_input="$FILTER_TARGETS"

    # CLI 未指定，尝试 config.json 的 targets 字段
    if [ -z "$targets_input" ]; then
        local config_targets=$(echo "$CONFIG" | jq -r '.targets // [] | join(",")' 2>/dev/null)
        if [ -n "$config_targets" ]; then
            targets_input="$config_targets"
        fi
    fi

    # 仍为空，从 rust-toolchain.toml 自动检测
    if [ -z "$targets_input" ]; then
        RESOLVED_TRIPLES=""
        RESOLVED_ARCHS=$(detect_targets_from_toolchain)
        return
    fi

    # 解析: 保留原始 triple, 同时提取短架构名
    local triples=()
    local archs=()
    IFS=',' read -ra items <<< "$targets_input"
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs) # trim
        [ -z "$item" ] && continue
        triples+=("$item")

        local arch=""
        case "$item" in
            *aarch64*) arch="aarch64" ;;
            *x86_64*) arch="x86_64" ;;
            *riscv64*) arch="riscv64" ;;
            *loongarch64*) arch="loongarch64" ;;
            *) log_warn "无法从 target '$item' 识别架构"; continue ;;
        esac
        if [[ " ${archs[*]} " != *" $arch "* ]]; then
            archs+=("$arch")
        fi
    done

    RESOLVED_TRIPLES="${triples[*]}"
    if [ ${#archs[@]} -eq 0 ]; then
        RESOLVED_ARCHS="all"
    else
        RESOLVED_ARCHS="${archs[*]}"
    fi
}

# 解析单元测试目标
# 优先级: CLI --unit-targets > config.json unit_test_targets > 跳过单元测试
# 设置全局变量: UNIT_TEST_TRIPLES - 空格分隔的完整 triple，为空则跳过单元测试
resolve_unit_test_targets() {
    local targets_input="$FILTER_UNIT_TARGETS"

    # CLI 未指定，尝试 config.json 的 unit_test_targets 字段
    if [ -z "$targets_input" ]; then
        local config_targets=$(echo "$CONFIG" | jq -r '.unit_test_targets // [] | join(",")' 2>/dev/null)
        if [ -n "$config_targets" ]; then
            targets_input="$config_targets"
        fi
    fi

    # 仍为空，跳过单元测试
    if [ -z "$targets_input" ]; then
        UNIT_TEST_TRIPLES=""
        return
    fi

    # 解析
    local triples=()
    IFS=',' read -ra items <<< "$targets_input"
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs)
        [ -z "$item" ] && continue
        triples+=("$item")
    done

    UNIT_TEST_TRIPLES="${triples[*]}"
}

# 解析 --suite 为匹配的 test_target 名称列表
# 优先级: CLI --suite > config.json test_targets > 全部
# 支持精确名称和前缀匹配 (如 "axvisor-qemu" 匹配 "axvisor-qemu-*")
# 输出: 空格分隔的 test_target 名称
resolve_suites() {
    local suite_input="$FILTER_SUITE"
    local all_names=()

    # 获取所有 test_target 名称
    local count=$(echo "$CONFIG" | jq '.test_targets | length')
    for ((i=0; i<count; i++)); do
        all_names+=("$(echo "$CONFIG" | jq -r ".test_targets[$i].name")")
    done

    # 未指定则返回全部
    if [ -z "$suite_input" ]; then
        echo "${all_names[*]}"
        return
    fi

    # 匹配: 支持精确名称和前缀
    local matched=()
    IFS=',' read -ra patterns <<< "$suite_input"
    for name in "${all_names[@]}"; do
        for pattern in "${patterns[@]}"; do
            pattern=$(echo "$pattern" | xargs) # trim
            if [ "$name" == "$pattern" ] || [[ "$name" == ${pattern}-* ]]; then
                matched+=("$name")
                break
            fi
        done
    done

    echo "${matched[*]}"
}

# 获取要测试的目标 (integration 模式)
# 计算 RESOLVED_ARCHS x resolve_suites() 的交集
# 不匹配架构的套件输出跳过提示
# 前置条件: resolve_targets() 已被调用
get_test_targets() {
    local resolved_suites=$(resolve_suites)
    local targets=()

    log_debug "过滤架构: $RESOLVED_ARCHS"
    log_debug "过滤套件: $resolved_suites"

    for suite_name in $resolved_suites; do
        local target_arch=$(echo "$CONFIG" | jq -r ".test_targets[] | select(.name == \"$suite_name\") | .arch")

        # 检查架构是否匹配
        local arch_matched=false
        if [ "$RESOLVED_ARCHS" == "all" ]; then
            arch_matched=true
        else
            for arch in $RESOLVED_ARCHS; do
                if [ "$target_arch" == "$arch" ]; then
                    arch_matched=true
                    break
                fi
            done
        fi

        if [ "$arch_matched" == true ]; then
            targets+=("$suite_name")
        else
            log_warn "[SKIP] $suite_name: 架构 $target_arch 不在 targets [${RESOLVED_ARCHS// /, }] 中，跳过"
        fi
    done

    echo "${targets[*]}"
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

    # 1. 克隆或更新仓库
    clone_or_update_repo "$target_name" "$repo_url" "$repo_branch" "$test_dir" "$log_file" "$status_file"
    if [ $? -ne 0 ]; then
        return 1
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

    # 2. 检查当前组件是否被目标项目使用
    if [[ "$target_name" == axvisor-* ]] || [[ "$target_name" == starry-* ]]; then
        if ! check_component_used "$target_name" "$test_dir"; then
            log_warn "  跳过测试: 当前组件 '$COMPONENT_CRATE' 未在 $target_name 的依赖中使用 (搜索目录: $test_dir)"
            echo "skipped" > "$status_file"
            return 2
        fi
    fi

    # 3. 应用 patch
    if ! apply_component_patch "$target_config" "$test_dir"; then
        log_error "  Patch 应用失败: $target_name"
        echo "failed" > "$status_file"
        return 1
    fi

    # 4. 执行构建
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
                actual_build_cmd="$build_cmd ARCH=$arch"
            fi

            if timeout "${timeout_min}m" sh -c "$actual_build_cmd" >> "$log_file" 2>&1; then
                # 为 starry 测试准备 rootfs
                if [[ "$target_name" == starry-* ]]; then
                    log "  准备 rootfs..."
                    local arch=$(echo "$target_config" | jq -r '.arch')
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

    # 5. 执行测试（如果有测试配置）
    local has_test=$(echo "$target_config" | jq 'has("test")')
    if [ "$has_test" == "true" ]; then
        local test_cmd=$(echo "$target_config" | jq -r '.test.command')
        local test_timeout=$(echo "$target_config" | jq -r '.test.timeout_minutes // 30')

        log "  运行测试... ($test_cmd, timeout: ${test_timeout}m)"

        # 准备测试命令和镜像（按类型分支）
        local full_test_cmd=""
        if [[ "$target_name" == axvisor-qemu-* ]]; then
            # QEMU 测试：下载镜像并配置
            if ! setup_qemu_images "$target_config" "$target_name" "$test_dir" "$log_file" "$status_file"; then
                cd "$COMPONENT_DIR"
                return 1
            fi
            full_test_cmd=$(prepare_qemu_command "$target_config")

        elif [[ "$target_name" == axvisor-board-* ]]; then
            # Board 测试：下载镜像、配置、defconfig、U-Boot
            if ! setup_board_images "$target_config" "$target_name" "$test_dir" "$log_file" "$status_file"; then
                cd "$COMPONENT_DIR"
                return 1
            fi

            cd "$test_dir"

            log "  生成构建配置..."
            if ! setup_board_defconfig "$target_config" "$target_name" "$test_dir" "$log_file" "$status_file"; then
                cd "$COMPONENT_DIR"
                return 1
            fi

            setup_uboot_config "$target_config" "$test_dir"
            full_test_cmd=$(prepare_board_command "$target_config")

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

# 运行单元测试 (cargo test)
# 如果有 UNIT_TEST_TRIPLES，为每个 triple 运行 cargo test --target <triple>
# 否则跳过单元测试
run_unit_tests() {
    local log_file="$OUTPUT_DIR/logs/unit_tests_$(date +%Y%m%d_%H%M%S).log"
    local status_file="$OUTPUT_DIR/unit_tests.status"

    # 未指定单元测试目标，跳过
    if [ -z "$UNIT_TEST_TRIPLES" ]; then
        log "跳过单元测试 (未配置 unit_test_targets)"
        echo "skipped" > "$status_file"
        return 2
    fi

    log "运行单元测试..."
    log_debug "  日志文件: $log_file"

    cd "$COMPONENT_DIR"

    # 有指定 targets，逐个运行
    local all_passed=true
    for triple in $UNIT_TEST_TRIPLES; do
        log "  cargo test --target $triple"
        if [ "$DRY_RUN" == true ]; then
            echo "[DRY-RUN] cd $COMPONENT_DIR && cargo test --target $triple"
        else
            if cargo test --target "$triple" >> "$log_file" 2>&1; then
                log_success "  单元测试通过: $triple"
            else
                log_error "  单元测试失败: $triple (详见日志: $log_file)"
                all_passed=false
            fi
        fi
    done

    if [ "$DRY_RUN" == true ]; then
        echo "skipped" > "$status_file"
        return 2
    elif [ "$all_passed" == true ]; then
        log_success "所有单元测试通过"
        echo "passed" > "$status_file"
        return 0
    else
        log_error "部分单元测试失败"
        echo "failed" > "$status_file"
        return 1
    fi
}

# 运行所有集成测试
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
    if [ $total_count -gt 3 ]; then
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
    if [ $passed -eq 0 ] && [ $skipped -gt 0 ]; then
        return 2
    fi
    return 0
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

    # 处理 --list-auto: 输出根据 targets x suite 过滤后的测试目标 (用于 CI matrix)
    if [ "$LIST_AUTO" == true ]; then
        # 保存原始 stderr，重定向到 /dev/null 以抑制所有日志输出
        exec 3>&2 2>/dev/null
        load_config
        resolve_targets
        local targets=$(get_test_targets)
        # 恢复 stderr 并输出 JSON
        exec 2>&3 3>&-
        echo "$targets" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s -c
        exit 0
    fi

    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Hypervisor Test Framework${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""

    check_dependencies
    load_config
    resolve_targets
    resolve_unit_test_targets

    log "配置加载完成"
    log "组件: $COMPONENT_NAME ($COMPONENT_CRATE)"
    if [ -n "$RESOLVED_TRIPLES" ]; then
        log_debug "Targets (triples): $RESOLVED_TRIPLES"
    fi
    if [ -n "$UNIT_TEST_TRIPLES" ]; then
        log_debug "Unit test targets: $UNIT_TEST_TRIPLES"
    fi
    log_debug "Targets (archs): $RESOLVED_ARCHS"

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

    local unit_result=0
    local integration_result=0
    local run_unit=false
    local run_integration=false

    # 根据测试模式决定运行哪些测试
    case "$TEST_TARGET" in
        all)
            run_unit=true
            run_integration=true
            ;;
        unit)
            run_unit=true
            ;;
        integration)
            run_integration=true
            ;;
        *)
            error "无效的测试模式: $TEST_TARGET (可选: all, unit, integration)"
            ;;
    esac

    # 运行单元测试
    if [ "$run_unit" == true ]; then
        echo ""
        log "========== 单元测试 =========="
        set +e
        run_unit_tests
        unit_result=$?
        set -e
    fi

    # 运行集成测试
    if [ "$run_integration" == true ]; then
        echo ""
        log "========== 集成测试 =========="
        set +e
        run_all_tests
        integration_result=$?
        set -e
    fi

    # 生成最终报告 (cleanup 由 EXIT trap 处理，无需显式调用)
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}  测试结果汇总${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"

    if [ "$run_unit" == true ]; then
        if [ $unit_result -eq 0 ]; then
            log_success "单元测试: 通过"
        elif [ $unit_result -eq 2 ]; then
            log_warn "单元测试: 跳过"
        else
            log_error "单元测试: 失败"
        fi
    fi

    if [ "$run_integration" == true ]; then
        if [ $integration_result -eq 0 ]; then
            log_success "集成测试: 通过"
        elif [ $integration_result -eq 2 ]; then
            log_warn "集成测试: 部分跳过"
        else
            log_error "集成测试: 部分失败"
        fi
    fi

    # 计算最终结果
    local final_result=0
    if [ "$run_unit" == true ] && [ $unit_result -ne 0 ] && [ $unit_result -ne 2 ]; then
        final_result=1
    fi
    if [ "$run_integration" == true ] && [ $integration_result -ne 0 ] && [ $integration_result -ne 2 ]; then
        final_result=1
    fi

    echo ""
    if [ $final_result -eq 0 ]; then
        log_success "所有测试通过!"
    else
        log_error "部分测试失败"
    fi

    exit $final_result
}

# 捕获信号
trap cleanup EXIT INT TERM

main "$@"
