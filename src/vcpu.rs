use aarch64_cpu::registers::{CNTHCTL_EL2, HCR_EL2, SPSR_EL1, VTCR_EL2};
use tock_registers::interfaces::ReadWriteable;

use axaddrspace::{GuestPhysAddr, HostPhysAddr};
use axerrno::AxResult;
use axvcpu::AxVCpuExitReason;

use crate::context_frame::VmContext;
use crate::exception_utils::exception_class_value;
use crate::irq::exception_handle_irq;
use crate::sync::exception_handle_sync;
use crate::TrapFrame;
// use crate::{do_register_lower_aarch64_irq_handler, do_register_lower_aarch64_synchronous_handler};

core::arch::global_asm!(include_str!("entry.S"));

/// (v)CPU register state that must be saved or restored when entering/exiting a VM or switching
/// between VMs.
#[repr(C)]
#[derive(Clone, Debug, Copy, Default)]
pub struct VmCpuRegisters {
    /// guest trap context
    pub trap_context_regs: TrapFrame,
    /// virtual machine system regs setting
    pub vm_system_regs: VmContext,
}

impl VmCpuRegisters {
    /// create a default VmCpuRegisters
    pub fn default() -> VmCpuRegisters {
        VmCpuRegisters {
            trap_context_regs: TrapFrame::default(),
            vm_system_regs: VmContext::default(),
        }
    }
}

/// A virtual CPU within a guest
#[derive(Clone, Debug)]
pub struct Aarch64VCpu {
    // DO NOT modify `guest_regs` and `host_stack_top` and their order unless you do know what you are doing!
    // DO NOT add anything before or between them unless you do know what you are doing!
    ctx: TrapFrame,
    host_stack_top: u64,
    system_regs: VmContext,
    vcpu_id: usize,
}

/// Indicates the parameter type used for creating a vCPU, currently using `VmCpuRegisters` directly.
pub type AxArchVCpuConfig = VmCpuRegisters;

impl axvcpu::AxArchVCpu for Aarch64VCpu {
    type CreateConfig = ();

    type SetupConfig = ();

    fn new(_config: Self::CreateConfig) -> AxResult<Self> {
        Ok(Self {
            ctx: TrapFrame::default(),
            host_stack_top: 0,
            system_regs: VmContext::default(),
            vcpu_id: 0, // need to pass a parameter!!!!
        })
    }

    fn setup(&mut self, _config: Self::SetupConfig) -> AxResult {
        // do_register_lower_aarch64_synchronous_handler()?;
        // do_register_lower_aarch64_irq_handler()?;
        self.init_hv();
        Ok(())
    }

    fn set_entry(&mut self, entry: GuestPhysAddr) -> AxResult {
        debug!("set vcpu entry:{:?}", entry);
        self.set_elr(entry.as_usize());
        Ok(())
    }

    fn set_ept_root(&mut self, ept_root: HostPhysAddr) -> AxResult {
        debug!("set vcpu ept root:{:#x}", ept_root);
        self.system_regs.vttbr_el2 = ept_root.as_usize() as u64;
        Ok(())
    }

    fn run(&mut self) -> AxResult<AxVCpuExitReason> {
        self.restore_vm_system_regs();
        let id: usize = self.run_guest();
        self.vmexit_handler(id)
    }

    fn bind(&mut self) -> AxResult {
        Ok(())
    }

    fn unbind(&mut self) -> AxResult {
        Ok(())
    }
}

// Private function
impl Aarch64VCpu {
    #[inline(never)]
    fn run_guest(&mut self) -> usize {
        let mut ret;
        unsafe {
            core::arch::asm!(
                save_regs_to_stack!(),  // save host context
                "mov x9, sp",
                "mov x10, {0}",
                "str x9, [x10]",    // save host stack top in the vcpu struct
                "mov x0, {0}",
                "b context_vm_entry",
                in(reg) &self.host_stack_top as *const _ as usize,
                out("x0") ret,
                options(nostack)
            );
        }
        ret
    }

    fn restore_vm_system_regs(&mut self) {
        unsafe {
            // load system regs
            core::arch::asm!(
                "
                mov x3, xzr           // Trap nothing from EL1 to El2.
                msr cptr_el2, x3"
            );
            self.system_regs.ext_regs_restore();
            core::arch::asm!(
                "
                ic  iallu
                tlbi	alle2
                tlbi	alle1         // Flush tlb
                dsb	nsh
                isb"
            );
        }
    }

    fn vmexit_handler(&mut self, id: usize) -> AxResult<AxVCpuExitReason> {
        trace!(
            "Aarch64VCpu vmexit_handler() esr:{:#x} ctx:{:#x?}",
            exception_class_value(),
            self.ctx
        );
        // restore system regs
        self.system_regs.ext_regs_store();

        let ctx = &mut self.ctx;
        match id {
            1 => return exception_handle_sync(ctx),
            2 => return exception_handle_irq(ctx),
            _ => panic!("undefined exception..."),
        }
    }

    fn init_hv(&mut self) {
        self.ctx.spsr = (SPSR_EL1::M::EL1h
            + SPSR_EL1::I::Masked
            + SPSR_EL1::F::Masked
            + SPSR_EL1::A::Masked
            + SPSR_EL1::D::Masked)
            .value;
        self.init_vm_context();
    }

    /// Init guest context. Also set some el2 register value.
    fn init_vm_context(&mut self) {
        CNTHCTL_EL2.modify(CNTHCTL_EL2::EL1PCEN::SET + CNTHCTL_EL2::EL1PCTEN::SET);
        self.system_regs.cntvoff_el2 = 0;
        self.system_regs.cntkctl_el1 = 0;

        self.system_regs.sctlr_el1 = 0x30C50830;
        self.system_regs.pmcr_el0 = 0;
        self.system_regs.vtcr_el2 = (VTCR_EL2::PS::PA_40B_1TB
            + VTCR_EL2::TG0::Granule4KB
            + VTCR_EL2::SH0::Inner
            + VTCR_EL2::ORGN0::NormalWBRAWA
            + VTCR_EL2::IRGN0::NormalWBRAWA
            + VTCR_EL2::SL0.val(0b01)
            + VTCR_EL2::T0SZ.val(64 - 39))
        .into();
        self.system_regs.hcr_el2 = (HCR_EL2::VM::Enable + HCR_EL2::RW::EL1IsAarch64).into();
        // self.system_regs.hcr_el2 |= 1<<27;
        // + HCR_EL2::IMO::EnableVirtualIRQ).into();
        // trap el1 smc to el2
        // self.system_regs.hcr_el2 |= HCR_TSC_TRAP as u64;

        let mut vmpidr = 0;
        vmpidr |= 1 << 31;
        vmpidr |= self.vcpu_id;
        self.system_regs.vmpidr_el2 = vmpidr as u64;
    }

    /// Set exception return pc
    fn set_elr(&mut self, elr: usize) {
        self.ctx.set_exception_pc(elr);
    }

    /// Get general purpose register
    #[allow(unused)]
    fn get_gpr(&self, idx: usize) {
        self.ctx.gpr(idx);
    }

    /// Set general purpose register
    #[allow(unused)]
    fn set_gpr(&mut self, idx: usize, val: usize) {
        self.ctx.set_gpr(idx, val);
    }
}

core::arch::global_asm!(include_str!("trap.S"));

#[naked]
#[no_mangle]
pub unsafe extern "C" fn vmexit_aarch64_handler() {
    // save guest context
    core::arch::asm!(
        "add sp, sp, 34 * 8", // skip the exception frame
        "mov x9, sp",
        "ldr x10, [x9]",
        "mov sp, x10",              // move sp to the host stack top value
        restore_regs_from_stack!(), // restore host context
        "ret",
        options(noreturn),
    )
}

#[repr(u8)]
#[derive(Debug)]
#[allow(dead_code)]
enum TrapKind {
    Synchronous = 0,
    Irq = 1,
    Fiq = 2,
    SError = 3,
}

#[repr(u8)]
#[derive(Debug)]
#[allow(dead_code)]
enum TrapSource {
    CurrentSpEl0 = 0,
    CurrentSpElx = 1,
    LowerAArch64 = 2,
    LowerAArch32 = 3,
}

/// deal with invalid aarch64 synchronous exception
#[no_mangle]
fn invalid_exception_el2(tf: &mut TrapFrame, kind: TrapKind, source: TrapSource) {
    panic!(
        "Invalid exception {:?} from {:?}:\n{:#x?}",
        kind, source, tf
    );
}
