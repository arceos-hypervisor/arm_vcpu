use axerrno::AxResult;
use axvcpu::AxVCpuExitReason;

use crate::TrapFrame;

// TODO: Handle current el irq and lower irq
// `vector: 33` is a temp res, we will remove it future
pub fn handle_exception_irq(_ctx: &mut TrapFrame) -> AxResult<AxVCpuExitReason> {
    Ok(AxVCpuExitReason::ExternalInterrupt { vector: 33 })
}
