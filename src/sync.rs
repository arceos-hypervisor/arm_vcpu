use axerrno::{AxError, AxResult};
use axvcpu::{AccessWidth, AxVCpuExitReason};

use crate::exception_utils::*;
use crate::TrapFrame;
use aarch64_cpu::registers::{
    Readable, ESR_EL2, HCR_EL2, SCTLR_EL1, VTCR_EL2, VTTBR_EL2,
};

pub fn exception_handle_sync(ctx: &mut TrapFrame) -> AxResult<AxVCpuExitReason> {
    match exception_class() {
        Some(ESR_EL2::EC::Value::DataAbortLowerEL) => return data_abort_handler(ctx),
        Some(ESR_EL2::EC::Value::HVC64) => {
            // Currently not used.
            let _hvc_arg_imm16 = ESR_EL2.read(ESR_EL2::ISS);
            // We assume that guest VM triggers HVC through a `hvc #0`` instruction.
            // And arm64 hcall implementation uses `x0` to specify the hcall number.
            // ref: [Linux](https://github.com/torvalds/linux/blob/master/Documentation/virt/kvm/arm/hyp-abi.rst)
            return Ok(AxVCpuExitReason::Hypercall {
                nr: ctx.gpr[0],
                args: [
                    ctx.gpr[1], ctx.gpr[2], ctx.gpr[3], ctx.gpr[4], ctx.gpr[5], ctx.gpr[6],
                ],
            });
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

pub fn data_abort_handler(context_frame: &mut TrapFrame) -> AxResult<AxVCpuExitReason> {
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
        return Ok(AxVCpuExitReason::MmioWrite {
            addr: address,
            width: access_width,
            data: context_frame.gpr(reg) as u64,
        });
    }
    Ok(AxVCpuExitReason::MmioRead {
        addr: address,
        width: access_width,
    })
}
