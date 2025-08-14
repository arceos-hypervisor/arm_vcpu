use core::marker::PhantomData;

use aarch64_cpu::registers::*;
use axerrno::AxResult;
use axvcpu::{AxArchPerCpu, AxVCpuHal};
use tock_registers::interfaces::ReadWriteable;

/// Per-CPU data. A pointer to this struct is loaded into TP when a CPU starts. This structure
#[repr(C)]
#[repr(align(4096))]
pub struct Aarch64PerCpu<H: AxVCpuHal> {
    /// per cpu id
    pub cpu_id: usize,
    _phantom: PhantomData<H>,
}

impl<H: AxVCpuHal> AxArchPerCpu for Aarch64PerCpu<H> {
    fn new(cpu_id: usize) -> AxResult<Self> {
        Ok(Self {
            cpu_id,
            _phantom: PhantomData,
        })
    }

    fn is_enabled(&self) -> bool {
        HCR_EL2.is_set(HCR_EL2::VM)
    }

    fn hardware_enable(&mut self) -> AxResult {
        HCR_EL2.modify(
            HCR_EL2::VM::Enable
                + HCR_EL2::RW::EL1IsAarch64
                + HCR_EL2::IMO::EnableVirtualIRQ
                + HCR_EL2::FMO::EnableVirtualFIQ
                + HCR_EL2::TSC::EnableTrapEl1SmcToEl2,
        );

        // Note that `ICH_HCR_EL2` is not the same as `HCR_EL2`.
        //
        // `ICH_HCR_EL2[0]` controls the virtual CPU interface operation.
        //
        // We leave it for the virtual GIC implementations to decide whether to enable it or not.
        //
        // unsafe {
        //     core::arch::asm! {
        //         "msr ich_hcr_el2, {value:x}",
        //         value = in(reg) 1,
        //     }
        // }

        Ok(())
    }

    fn hardware_disable(&mut self) -> AxResult {
        HCR_EL2.set(HCR_EL2::VM::Disable.into());
        Ok(())
    }
}
