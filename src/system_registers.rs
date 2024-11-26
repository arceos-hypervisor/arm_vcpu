extern crate alloc;
use crate::vcpu::Aarch64VCpu;
use aarch64_sysreg::SystemRegType;
use alloc::sync::Arc;
use alloc::vec::Vec;
use axvcpu::{AxVCpu, AxVCpuHal};
use spin::RwLock;

type RegVcpu<H> = Arc<AxVCpu<Aarch64VCpu<H>>>;

/// Struct representing an entry in the emulator register list.
pub struct EmuRegEntry<H: AxVCpuHal> {
    /// The type of the emulator register.
    pub emu_type: EmuRegType,
    /// The address associated with the emulator register.
    pub addr: SystemRegType,
    /// The handler write function for the emulator register.
    pub handle_write: fn(SystemRegType, usize, u64, RegVcpu<H>) -> bool,
    /// The handler read function for the emulator register.
    pub handle_read: fn(SystemRegType, usize, RegVcpu<H>) -> bool,
}

/// Enumeration representing the type of emulator registers.
pub enum EmuRegType {
    /// System register type for emulator registers.
    SysReg,
}

/// Struct representing the emulator registers.
pub struct Aarch64EmuRegs<H: AxVCpuHal> {
    /// The list of emulator registers.
    pub emu_regs: RwLock<Vec<EmuRegEntry<H>>>,
}

impl<H: AxVCpuHal> Aarch64EmuRegs<H> {
    const EMU_REGISTERS: RwLock<Vec<EmuRegEntry<H>>> = RwLock::new(Vec::new());

    /// Handle a write to an emulator register.
    pub fn emu_register_handle_write(
        addr: SystemRegType,
        reg: usize,
        value: u64,
        vcpu: RegVcpu<H>,
    ) -> bool {
        let binding = Self::EMU_REGISTERS;
        let emu_reg = binding.read();

        for entry in emu_reg.iter() {
            if entry.addr == addr {
                return (entry.handle_write)(addr, reg, value, vcpu);
            }
        }
        error!("Invalid emulated register write: addr={}", addr);
        false
    }

    /// Handle a read from an emulator register.
    pub fn emu_register_handle_read(addr: SystemRegType, reg: usize, vcpu: RegVcpu<H>) -> bool {
        let binding = Self::EMU_REGISTERS;
        let emu_reg = binding.read();

        for entry in emu_reg.iter() {
            if entry.addr == addr {
                return (entry.handle_read)(addr, reg, vcpu);
            }
        }
        error!("Invalid emulated register read: addr={}", addr);
        false
    }
}
