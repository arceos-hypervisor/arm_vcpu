use core::marker::PhantomData;

use aarch64_cpu::registers::*;
use tock_registers::interfaces::ReadWriteable;

use axerrno::AxResult;
use axvcpu::{AxArchPerCpu, AxVCpuHal};

/// Per-CPU data. A pointer to this struct is loaded into TP when a CPU starts. This structure
#[repr(C)]
#[repr(align(4096))]
pub struct Aarch64PerCpu<H: AxVCpuHal> {
    //stack_top_addr has no use yet?
    /// per cpu id
    pub cpu_id: usize,
    /// context address of this cpu
    pub ctx: Option<usize>,
    _phantom: PhantomData<H>,
}

#[percpu::def_percpu]
static ORI_EXCEPTION_VECTOR_BASE: usize = 0;

extern "C" {
    fn exception_vector_base_vcpu();
}

impl<H: AxVCpuHal> AxArchPerCpu for Aarch64PerCpu<H> {
    fn new(cpu_id: usize) -> AxResult<Self> {
        Ok(Self {
            cpu_id,
            ctx: None,
            _phantom: PhantomData,
        })
    }

    fn is_enabled(&self) -> bool {
        HCR_EL2.is_set(HCR_EL2::VM)
    }

    fn hardware_enable(&mut self) -> AxResult {
        // First we save origin `exception_vector_base`.
        // Safety:
        // Todo: take care of `preemption`
        unsafe { ORI_EXCEPTION_VECTOR_BASE.write_current_raw(VBAR_EL2.get() as usize) }

        // Set current `VBAR_EL2` to `exception_vector_base_vcpu`
        // defined in this crate.
        VBAR_EL2.set(exception_vector_base_vcpu as usize as _);

        HCR_EL2.modify(
            HCR_EL2::VM::Enable
                + HCR_EL2::RW::EL1IsAarch64
                + HCR_EL2::IMO::EnableVirtualIRQ
                + HCR_EL2::FMO::EnableVirtualFIQ
                + HCR_EL2::TSC::EnableTrapEl1SmcToEl2,
        );

        Ok(())
    }

    fn hardware_disable(&mut self) -> AxResult {
        // Reset `VBAR_EL2` into previous value.
        // Safety:
        // Todo: take care of `preemption`
        VBAR_EL2.set(unsafe { ORI_EXCEPTION_VECTOR_BASE.read_current_raw() } as _);

        HCR_EL2.set(HCR_EL2::VM::Disable.into());
        Ok(())
    }
}
