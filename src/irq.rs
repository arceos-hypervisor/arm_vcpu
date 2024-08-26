use axerrno::AxResult;
use axvcpu::AxVCpuExitReason;

use crate::TrapFrame;


pub fn exception_handle_irq(_ctx: &mut TrapFrame) -> AxResult<AxVCpuExitReason> {
    Ok(
        AxVCpuExitReason::ExternalInterrupt {
            vector: 33
        }
    )
}
