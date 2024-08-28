use aarch64_cpu::registers::{Readable, ESR_EL2, HCR_EL2, SCTLR_EL1, VTCR_EL2, VTTBR_EL2};

use axerrno::{AxError, AxResult};
use axvcpu::{AccessWidth, AxVCpuExitReason};

use crate::exception_utils::{
    exception_class, exception_class_value, exception_data_abort_access_is_write,
    exception_data_abort_access_reg, exception_data_abort_access_width, exception_esr,
    exception_fault_addr, exception_next_instruction_step,
};
use crate::TrapFrame;

numeric_enum_macro::numeric_enum! {
#[repr(u8)]
#[derive(Debug)]
pub enum TrapKind {
    Synchronous = 0,
    Irq = 1,
    Fiq = 2,
    SError = 3,
}
}

/// This is equal to the type defined by the `TrapKind` enum.
/// TODO: How can we reuse `TrapKind` directly?
const EXCEPTION_SYNC: usize = 0;
const EXCEPTION_IRQ: usize = 1;

#[repr(u8)]
#[derive(Debug)]
#[allow(unused)]
enum TrapSource {
    CurrentSpEl0 = 0,
    CurrentSpElx = 1,
    LowerAArch64 = 2,
    LowerAArch32 = 3,
}

core::arch::global_asm!(
    include_str!("exception.S"),
    exception_sync = const EXCEPTION_SYNC,
    exception_irq = const EXCEPTION_IRQ,
);

/// Handles IRQ (Interrupt Request) exceptions that occur during the execution of a guest VM.
///
/// This function is responsible for processing external interrupts.
///
/// # Arguments
///
/// * `_ctx` - A mutable reference to the `TrapFrame`, which contains the saved state of the
///            guest VM's CPU registers at the time of the exception. This is currently unused
///            but included for future expansion.
///
/// # Returns
///
/// An `AxResult` containing an `AxVCpuExitReason` with the reason for the VM exit.
///
/// # TODO
///
/// - Implement proper handling of both current and lower EL IRQs.
/// - Replace the temporary vector `33` with the actual interrupt vector once the
///   full implementation is complete.
///
/// # Notes
///
/// This function is a placeholder and should be expanded to fully support IRQ handling
/// in future iterations.
///
pub fn handle_exception_irq(_ctx: &mut TrapFrame) -> AxResult<AxVCpuExitReason> {
    Ok(AxVCpuExitReason::ExternalInterrupt { vector: 33 })
}

/// Handles synchronous exceptions that occur during the execution of a guest VM.
///
/// This function examines the exception class (EC) to determine the cause of the exception
/// and then handles it accordingly.
///
/// Currently we just handle exception type including data abort (`DataAbortLowerEL`) and hypervisor call (`HVC64)`.
///
/// # Arguments
///
/// * `ctx` - A mutable reference to the `TrapFrame`, which contains the saved state of the
///           guest VM's CPU registers at the time of the exception.
///
/// # Returns
///
/// An `AxResult` containing an `AxVCpuExitReason` indicating the reason for the VM exit.
/// This could be due to a hypervisor call (`Hypercall`) or other reasons such as data aborts.
///
/// # Panics
///
/// If an unhandled exception class is encountered, the function will panic, outputting
/// details about the exception including the instruction pointer, faulting address, exception
/// syndrome register (ESR), and system control registers.
///
pub fn handle_exception_sync(ctx: &mut TrapFrame) -> AxResult<AxVCpuExitReason> {
    match exception_class() {
        Some(ESR_EL2::EC::Value::DataAbortLowerEL) => handle_data_abort(ctx),
        Some(ESR_EL2::EC::Value::HVC64) => {
            // The `#imm`` argument when triggering a hvc call, currently not used.
            let _hvc_arg_imm16 = ESR_EL2.read(ESR_EL2::ISS);

            // We assume that guest VM triggers HVC through a `hvc #0`` instruction.
            // And arm64 hcall implementation uses `x0` to specify the hcall number.
            // For more details on the hypervisor call (HVC) mechanism and the use of general-purpose registers,
            // refer to the [Linux Kernel documentation on KVM ARM hypervisor ABI](https://github.com/torvalds/linux/blob/master/Documentation/virt/kvm/arm/hyp-abi.rst).
            Ok(AxVCpuExitReason::Hypercall {
                nr: ctx.gpr[0],
                args: [
                    ctx.gpr[1], ctx.gpr[2], ctx.gpr[3], ctx.gpr[4], ctx.gpr[5], ctx.gpr[6],
                ],
            })
        }
        _ => {
            panic!(
                "handler not presents for EC_{} @ipa 0x{:x}, @pc 0x{:x}, @esr 0x{:x},
                @sctlr_el1 0x{:x}, @vttbr_el2 0x{:x}, @vtcr_el2: {:#x} hcr: {:#x} ctx:{}",
                exception_class_value(),
                exception_fault_addr()?,
                (*ctx).exception_pc(),
                exception_esr(),
                SCTLR_EL1.get() as usize,
                VTTBR_EL2.get() as usize,
                VTCR_EL2.get() as usize,
                HCR_EL2.get() as usize,
                ctx
            );
        }
    }
}

fn handle_data_abort(context_frame: &mut TrapFrame) -> AxResult<AxVCpuExitReason> {
    let address = exception_fault_addr()?;
    debug!(
        "data fault addr {:?}, esr: 0x{:x}",
        address,
        exception_esr()
    );

    let width = exception_data_abort_access_width();
    let is_write = exception_data_abort_access_is_write();
    // let sign_ext = exception_data_abort_access_is_sign_ext();
    let reg = exception_data_abort_access_reg();
    // let reg_width = exception_data_abort_access_reg_width();

    let elr = context_frame.exception_pc();
    let val = elr + exception_next_instruction_step();
    context_frame.set_exception_pc(val);

    let access_width = match AccessWidth::try_from(width) {
        Ok(width) => width,
        Err(_) => return Err(AxError::InvalidInput),
    };

    if is_write {
        Ok(AxVCpuExitReason::MmioWrite {
            addr: address,
            width: access_width,
            data: context_frame.gpr(reg) as u64,
        })
    } else {
        Ok(AxVCpuExitReason::MmioRead {
            addr: address,
            width: access_width,
        })
    }
}

/// A trampoline function for sp switching during handling VM exits.
/// # Functionality
///
/// 1. **Restore Previous Host Stack pointor:**
///     - The guest context frame is aleady saved by `SAVE_REGS_FROM_EL1` macro in exception.S.
///       This function firstly adjusts the `sp` to skip the exception frame
///       (adding `34 * 8` to the stack pointer) according to the memory layout of `Aarch64VCpu` struct,
///       which makes current `sp` point to the address of `host_stack_top`.
///       The host stack top value is restored by `ldr`.
///
/// 2. **Restore Host Context:**
///     - The `restore_regs_from_stack!()` macro is invoked to restore the host function context
///       from the stack. This macro handles the restoration of the host's callee-saved general-purpose
///       registers (`x19` to `x30`).
///
/// 3. **Restore Host Control Flow:**
///     - The `ret` instruction is used to return control to the host context after
///       the guest context has been saved in `Aarch64VCpu` struct and the host context restored.
///       Finally the control flow is returned back to `Aarch64VCpu.run()` in [vcpu.rs].
///
/// # Notes
///
/// - This function is typically invoked when a VM exit occurs, requiring the
///   hypervisor to switch context from the guest to the host. The precise control
///   over stack and register management ensures that the transition is smooth and
///   that the host can correctly resume execution.
///
/// - The `options(noreturn)` directive indicates that this function will not return
///   to its caller, as control will be transferred back to the host context via `ret`.
///
/// - This function is not typically called directly from Rust code. Instead, it is
///   invoked as part of the low-level hypervisor or VM exit handling routines.
#[naked]
#[no_mangle]
unsafe extern "C" fn vmexit_trampoline() {
    // Note: Currently `sp` points to `&Aarch64VCpu.ctx`, which is just the base address of Aarch64VCpu struct.
    core::arch::asm!(
        "add sp, sp, 34 * 8",       // Skip the exception frame.
        "mov x9, sp", // Currently `sp` points to `&Aarch64VCpu.host_stack_top`, see `run_guest()` in vcpu.rs.
        "ldr x10, [x9]", // Get `host_stack_top` value from `&Aarch64VCpu.host_stack_top`.
        "mov sp, x10", // Set `sp` as the host stack top.
        restore_regs_from_stack!(), // Restore host function context frame.
        "ret", // Control flow is handed back to Aarch64VCpu.run(), simulating the normal return of the `run_guest` function.
        options(noreturn),
    )
}

/// Deal with invalid aarch64 exception.
#[no_mangle]
fn invalid_exception_el2(tf: &mut TrapFrame, kind: TrapKind, source: TrapSource) {
    panic!(
        "Invalid exception {:?} from {:?}:\n{:#x?}",
        kind, source, tf
    );
}