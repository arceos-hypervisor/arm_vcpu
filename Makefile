# arm_vcpu Makefile
# 简化本地开发和测试流程

.PHONY: all check build test test-axvisor test-starry clean help

# 默认目标
all: check

# 代码检查
check:
	@echo "Running cargo check..."
	cargo check --target aarch64-unknown-none-softfloat

# 构建
build:
	@echo "Building..."
	cargo build --target aarch64-unknown-none-softfloat --release

# 运行所有测试 (使用共享测试框架)
test:
	@echo "Running all tests..."
	./scripts/run_tests.sh

# 仅运行 axvisor 测试
test-axvisor:
	@echo "Running axvisor integration test..."
	./scripts/run_tests.sh --target axvisor

# 仅运行 StarryOS 测试
test-starry:
	@echo "Running StarryOS integration test..."
	./scripts/run_tests.sh --target starry

# 代码格式检查
fmt:
	@echo "Checking code format..."
	cargo fmt --check

# 运行 clippy
clippy:
	@echo "Running clippy..."
	cargo clippy --target aarch64-unknown-none-softfloat -- -D warnings

# 完整的 CI 检查（本地模拟）
ci-local: fmt clippy check
	@echo "All CI checks passed!"

# 清理
clean:
	@echo "Cleaning..."
	cargo clean
	rm -rf test-results

# 帮助
help:
	@echo "arm_vcpu Makefile"
	@echo ""
	@echo "可用目标:"
	@echo "  check        - 运行 cargo check"
	@echo "  build        - 构建项目"
	@echo "  test         - 运行所有集成测试 (使用共享测试框架)"
	@echo "  test-axvisor - 运行 axvisor 集成测试"
	@echo "  test-starry  - 运行 StarryOS 集成测试"
	@echo "  fmt          - 检查代码格式"
	@echo "  clippy       - 运行 clippy 检查"
	@echo "  ci-local     - 运行完整的 CI 检查（本地模拟）"
	@echo "  clean        - 清理构建产物"
	@echo "  help         - 显示此帮助信息"
	@echo ""
	@echo "测试框架: https://github.com/arceos-hypervisor/hypervisor-test-framework"
