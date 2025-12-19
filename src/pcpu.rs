use aarch64_cpu::registers::*;
use axerrno::AxResult;

/// Per-CPU data. A pointer to this struct is loaded into TP when a CPU starts. This structure
#[repr(C)]
#[repr(align(4096))]
pub struct Aarch64PerCpu {
    ori_vbar: u64,
}

unsafe extern "C" {
    fn exception_vector_base_vcpu();
}

impl Aarch64PerCpu {
    pub fn new() -> Self {
        Self {
            ori_vbar: VBAR_EL2.get(),
        }
    }

    pub fn is_enabled(&self) -> bool {
        HCR_EL2.is_set(HCR_EL2::VM)
    }

    pub fn hardware_enable(&mut self) {
        // Set current `VBAR_EL2` to `exception_vector_base_vcpu`
        // defined in this crate.
        VBAR_EL2.set(exception_vector_base_vcpu as usize as _);

        HCR_EL2.modify(
            HCR_EL2::VM::Enable + HCR_EL2::RW::EL1IsAarch64 + HCR_EL2::TSC::EnableTrapEl1SmcToEl2,
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
        //         value = in(reg) 0,
        //     }
        // }
    }

    pub fn hardware_disable(&mut self) -> AxResult {
        // Reset `VBAR_EL2` into previous value.
        // Safety:
        // Todo: take care of `preemption`
        VBAR_EL2.set(self.ori_vbar);

        HCR_EL2.set(HCR_EL2::VM::Disable.into());
        Ok(())
    }

    pub fn max_guest_page_table_levels(&self) -> usize {
        crate::vcpu::max_gpt_level(crate::vcpu::pa_bits())
    }

    pub fn pa_range(&self) -> core::ops::Range<usize> {
        let pa_bits = crate::vcpu::pa_bits();
        0..(1 << pa_bits)
    }
}
