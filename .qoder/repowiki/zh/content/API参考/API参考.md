# API参考

<cite>
**本文档中引用的文件**
- [lib.rs](file://src/lib.rs)
- [vcpu.rs](file://src/vcpu.rs)
- [pcpu.rs](file://src/pcpu.rs)
</cite>

## 目录
1. [简介](#简介)
2. [核心API概览](#核心api概览)
3. [Aarch64VCpu结构体](#aarch64vcpu结构体)
   - [构造函数 `new`](#构造函数-new)
   - [运行控制方法 `run`](#运行控制方法-run)
   - [入口地址设置 `set_entry`](#入口地址设置-set_entry)
   - [页表根设置 `set_ept_root`](#页表根设置-set_ept_root)
4. [Aarch64PerCpu结构体](#aarch64percpu结构体)
   - [硬件启用 `hardware_enable`](#硬件启用-hardware_enable)
   - [硬件禁用 `hardware_disable`](#硬件禁用-hardware_disable)
5. [全局支持检测函数](#全局支持检测函数)
   - [`has_hardware_support()`](#has_hardware_support)
6. [使用示例](#使用示例)

## 简介

`arm_vcpu` 库为基于 AArch64 架构的虚拟 CPU（vCPU）提供了底层操作接口。本技术文档详细记录了所有公共 API，包括 vCPU 的创建、配置、运行控制以及物理 CPU（pCPU）的硬件虚拟化功能管理。文档重点覆盖 `Aarch64VCpu` 和 `Aarch64PerCpu` 两个核心结构体的公共方法，以及用于检测平台虚拟化支持的全局函数。

所有 API 的描述均严格依据 `lib.rs` 中的模块导出声明和 `vcpu.rs`、`pcpu.rs` 中的具体实现，确保信息与源码完全一致。

## 核心API概览

本库的核心功能围绕以下三个主要组件展开：

1.  **`Aarch64VCpu`**: 代表一个在客户机（guest）环境中的虚拟 CPU，负责管理其寄存器状态、执行流程和内存映射。
2.  **`Aarch64PerCpu`**: 代表宿主机上的每个物理 CPU，用于启用和禁用该物理核上的硬件虚拟化扩展。
3.  **`has_hardware_support`**: 全局函数，用于查询当前平台是否支持 ARM 虚拟化扩展。

这些组件共同构成了一个轻量级的 AArch64 vCPU 框架，允许开发者在 EL2 特权级下构建和管理虚拟机。

## Aarch64VCpu结构体

`Aarch64VCpu<H>` 是库中的核心数据结构，它封装了一个 vCPU 的完整上下文，包括通用寄存器、系统寄存器和运行时状态。泛型参数 `H` 实现了 `AxVCpuHal` trait，用于提供与宿主操作系统交互的钩子（hooks）。

### 构造函数 `new`

此方法用于创建一个新的 `Aarch64VCpu` 实例。

**Section sources**
- [vcpu.rs](file://src/vcpu.rs#L98-L107)

#### 方法签名
```rust
fn new(_vm_id: usize, _vcpu_id: usize, config: Self::CreateConfig) -> AxResult<Self>
```

#### 参数
- `_vm_id`: 所属虚拟机的 ID（目前未使用）。
- `_vcpu_id`: 此 vCPU 在虚拟机内的 ID（目前未使用）。
- `config`: 一个 `Aarch64VCpuCreateConfig` 结构体，包含创建 vCPU 所需的配置。

#### 返回值
- `AxResult<Self>`: 成功时返回新创建的 `Aarch64VCpu` 实例；失败时返回 `axerrno::AxError` 错误码。

#### 配置参数 (`Aarch64VCpuCreateConfig`)
- `mpidr_el1`: u64 - 为此 vCPU 设置的 MPIDR_EL1 值，用于在多处理器系统中标识 CPU。
- `dtb_addr`: usize - 设备树二进制文件（DTB）的物理地址。

#### 错误码及触发条件
- 当前实现中，`new` 方法总是成功返回 `Ok`，不会产生错误。初始化过程不涉及可能失败的硬件操作。

#### 内联代码示例
```rust
let create_config = Aarch64VCpuCreateConfig {
    mpidr_el1: 0x80000000,
    dtb_addr: 0x40000000,
};
let mut vcpu = Aarch64VCpu::new(0, 0, create_config)?;
```

### 运行控制方法 `run`

此方法是 vCPU 的核心执行入口，它将控制权从宿主机（EL2）切换到客户机（EL1），并开始执行客户机代码。

**Section sources**
- [vcpu.rs](file://src/vcpu.rs#L130-L142)

#### 方法签名
```rust
fn run(&mut self) -> AxResult<AxVCpuExitReason>
```

#### 参数
- `self`: 可变借用的 `Aarch64VCpu` 实例。

#### 返回值
- `AxResult<AxVCpuExitReason>`: 成功时返回 `AxVCpuExitReason` 枚举，指示导致 VM-Exit（从客户机退出到宿主机）的原因；失败时返回错误码。

#### 错误码及触发条件
- 当前实现中，`run` 方法本身不会返回错误，但会通过 `AxVCpuExitReason` 报告各种异常情况。
- 如果在处理同步异常（如缺页、非法指令）时遇到无法处理的情况，代码会调用 `panic!`，这会导致程序终止而非返回可恢复的错误。

#### 工作流程
1.  保存宿主机的 `SP_EL0` 寄存器。
2.  恢复客户机的系统寄存器（如 `VTCR_EL2`, `HCR_EL2`）。
3.  通过汇编代码 `context_vm_entry` 切换到客户机模式并开始执行。
4.  当发生 VM-Exit 时，控制流返回，并调用 `vmexit_handler` 处理退出原因。

#### 内联代码示例
```rust
loop {
    match vcpu.run() {
        Ok(exit_reason) => {
            // 根据 exit_reason 进行相应的处理
            handle_exit_reason(exit_reason);
        }
        Err(e) => {
            // 处理错误（尽管当前很少发生）
            log::error!("vCPU 运行出错: {:?}", e);
            break;
        }
    }
}
```

### 入口地址设置 `set_entry`

此方法用于设置 vCPU 开始执行时的程序计数器（PC）地址。

**Section sources**
- [vcpu.rs](file://src/vcpu.rs#L117-L122)

#### 方法签名
```rust
fn set_entry(&mut self, entry: GuestPhysAddr) -> AxResult
```

#### 参数
- `entry`: `GuestPhysAddr` 类型 - 客户机代码的入口点物理地址。

#### 返回值
- `AxResult`: 操作成功返回 `Ok(())`。

#### 错误码及触发条件
- 当前实现中，此方法总是成功返回 `Ok(())`，因为只是简单地将地址写入内部上下文。

#### 内联代码示例
```rust
// 假设内核镜像加载在 0x40200000
let kernel_entry: GuestPhysAddr = 0x40200000.into();
vcpu.set_entry(kernel_entry)?;
```

### 页表根设置 `set_ept_root`

此方法用于设置第二阶段转换（Stage 2 Translation）的页表根地址，即 VTTBR_EL2 寄存器的值。

**Section sources**
- [vcpu.rs](file://src/vcpu.rs#L124-L129)

#### 方法签名
```rust
fn set_ept_root(&mut self, ept_root: HostPhysAddr) -> AxResult
```

#### 参数
- `ept_root`: `HostPhysAddr` 类型 - 指向宿主机物理内存中 EPT（嵌套分页）页表根节点的地址。

#### 返回值
- `AxResult`: 操作成功返回 `Ok(())`。

#### 错误码及触发条件
- 当前实现中，此方法总是成功返回 `Ok(())`，因为它只是将传入的地址赋值给内部的 `guest_system_regs.vttbr_el2` 字段。

#### 内联代码示例
```rust
// 假设已创建好 EPT 页表，其根节点的宿主机物理地址为 hpa
let ept_root: HostPhysAddr = hpa.into();
vcpu.set_ept_root(ept_root)?;
```

## Aarch64PerCpu结构体

`Aarch64PerCpu<H>` 结构体用于管理宿主机上单个物理 CPU 的虚拟化状态。每个物理核都需要一个对应的实例来启用或禁用其硬件虚拟化功能。

### 硬件启用 `hardware_enable`

此方法在当前物理 CPU 上启用硬件虚拟化扩展。

**Section sources**
- [pcpu.rs](file://src/pcpu.rs#L58-L81)

#### 方法签名
```rust
fn hardware_enable(&mut self) -> AxResult
```

#### 参数
- `self`: 可变借用的 `Aarch64PerCpu` 实例。

#### 返回值
- `AxResult`: 成功返回 `Ok(())`。

#### 错误码及触发条件
- 当前实现中，此方法总是成功返回 `Ok(())`。

#### 工作流程
1.  保存当前的异常向量基址寄存器 `VBAR_EL2` 的值。
2.  将 `VBAR_EL2` 设置为指向本库定义的 `exception_vector_base_vcpu`，以便捕获来自客户机的所有异常。
3.  配置 `HCR_EL2` (Hypervisor Configuration Register)：
    -   `VM=1`: 启用虚拟化模式。
    -   `RW=1`: 指定客户机在 AArch64 模式下运行。
    -   `IMO=1`: 启用虚拟 IRQ，将物理 IRQ 陷阱到 EL2。
    -   `FMO=1`: 启用虚拟 FIQ。
    -   `TSC=1`: 陷阱 EL1 的 SMC 指令到 EL2。

#### 内联代码示例
```rust
let cpu_id = 0; // 当前 CPU ID
let mut per_cpu = Aarch64PerCpu::new(cpu_id)?;
per_cpu.hardware_enable()?;
```

### 硬件禁用 `hardware_disable`

此方法在当前物理 CPU 上禁用硬件虚拟化扩展，将其恢复到正常操作模式。

**Section sources**
- [pcpu.rs](file://src/pcpu.rs#L83-L91)

#### 方法签名
```rust
fn hardware_disable(&mut self) -> AxResult
```

#### 参数
- `self`: 可变借用的 `Aarch64PerCpu` 实例。

#### 返回值
- `AxResult`: 成功返回 `Ok(())`。

#### 错误码及触发条件
- 当前实现中，此方法总是成功返回 `Ok(())`。

#### 工作流程
1.  将 `VBAR_EL2` 恢复为之前保存的原始异常向量基址。
2.  清除 `HCR_EL2` 的 `VM` 位，从而禁用虚拟化模式。

#### 内联代码示例
```rust
// 在关闭虚拟机或卸载模块时调用
per_cpu.hardware_disable()?;
```

## 全局支持检测函数

### `has_hardware_support`

这是一个全局函数，用于检查当前平台是否支持 ARM 虚拟化扩展。

**Section sources**
- [lib.rs](file://src/lib.rs#L19-L29)

#### 函数签名
```rust
pub fn has_hardware_support() -> bool
```

#### 参数
- 无。

#### 返回值
- `bool`: 如果平台支持虚拟化扩展，则返回 `true`；否则返回 `false`。

#### 实现说明
- **重要提示**：当前的实现是一个占位符，直接返回 `true`。
- 注释中指出，正确的实现应该读取 `ID_AA64MMFR1_EL1` 系统寄存器来检查 "Virtualization Host Extensions" 是否被支持。
- 因此，此函数的返回值不能作为实际硬件能力的可靠判断依据，开发者需要自行实现完整的检测逻辑。

#### 内联代码示例
```rust
if has_hardware_support() {
    log::info!("硬件虚拟化支持已就绪");
    // 继续初始化 vCPU
} else {
    log::warn!("硬件虚拟化不受支持");
    // 采取备用方案或报错
}
```

## 使用示例

以下是一个综合性的代码片段，展示了如何使用上述 API 来初始化一个 vCPU 并准备运行。

```rust
// 1. 为当前物理 CPU 启用硬件虚拟化
let mut per_cpu = Aarch64PerCpu::new(current_cpu_id)?;
per_cpu.hardware_enable()?;

// 2. 创建 vCPU 配置
let create_config = Aarch64VCpuCreateConfig {
    mpidr_el1: current_cpu_id as u64,
    dtb_addr: guest_dtb_paddr,
};

// 3. 创建 vCPU 实例
let mut vcpu = Aarch64VCpu::new(0, 0, create_config)?;

// 4. 设置 vCPU 的初始配置
let setup_config = Aarch64VCpuSetupConfig {
    passthrough_interrupt: false,
    passthrough_timer: true,
};
vcpu.setup(setup_config)?;

// 5. 配置 vCPU 的执行环境
vcpu.set_entry(kernel_entry_point)?; // 设置内核入口
vcpu.set_ept_root(host_ept_root)?;   // 设置 EPT 页表根

// 6. 进入主循环，运行 vCPU
loop {
    match vcpu.run() {
        Ok(AxVCpuExitReason::ExternalInterrupt { vector }) => {
            // 处理外部中断
            handle_guest_irq(vector);
        }
        Ok(AxVCpuExitReason::SysCall { .. }) => {
            // 处理系统调用
            handle_guest_syscall();
        }
        Ok(AxVCpuExitReason::Nothing) => {
            // 继续运行
            continue;
        }
        Ok(other) => {
            // 处理其他退出原因
            log::debug!("未知的 VM-Exit 原因: {:?}", other);
        }
        Err(e) => {
            log::error!("vCPU 运行失败: {:?}", e);
            break;
        }
    }
}

// 7. 清理：禁用硬件虚拟化
per_cpu.hardware_disable()?;
```