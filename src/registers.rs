extern crate alloc;
use crate::vcpu::Aarch64VCpu;
use aarch64_cpu::registers::{Readable, Writeable};
use aarch64_cpu::registers::{CNTFRQ_EL0, CNTPCT_EL0, CNTP_CTL_EL0, CNTP_TVAL_EL0};
use aarch64_sysreg::SystemRegType;
use alloc::sync::Arc;
use alloc::{vec, vec::Vec};
pub use arm_gicv2::GicInterface;
use axvcpu::{AxArchVCpu, AxVCpu};
use lazy_static::lazy_static;
use spin::RwLock;

/// Struct representing an entry in the emulator register list.
pub struct EmuRegEntry {
    /// The type of the emulator register.
    pub emu_type: EmuRegType,
    /// The address associated with the emulator register.
    pub addr: SystemRegType,
    /// The handler write function for the emulator register.
    pub handle_write: fn(SystemRegType, usize, u64, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
    /// The handler read function for the emulator register.
    pub handle_read: fn(SystemRegType, usize, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
}

/// Enumeration representing the type of emulator registers.
pub enum EmuRegType {
    /// System register type for emulator registers.
    SysReg,
}

pub fn emu_register_add(
    addr: SystemRegType,
    handle_write: fn(SystemRegType, usize, u64, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
    handle_read: fn(SystemRegType, usize, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
) {
    let mut emu_reg = EMU_REGISTERS.write();
    for entry in emu_reg.iter() {
        if entry.addr == addr {
            error!("Register:{} already exists", addr);
            return;
        }
    }
    info!("Register:{} added", addr);
    emu_reg.push(EmuRegEntry {
        emu_type: EmuRegType::SysReg,
        addr,
        handle_write,
        handle_read,
    });
}

pub fn emu_register_handle_write(
    addr: SystemRegType,
    reg: usize,
    value: u64,
    vcpu: Arc<AxVCpu<Aarch64VCpu>>,
) -> bool {
    let emu_reg = EMU_REGISTERS.read();
    for entry in emu_reg.iter() {
        if entry.addr == addr {
            return (entry.handle_write)(addr, reg, value, vcpu);
        }
    }
    panic!("Invalid emulated register write: addr={}", addr);
}

pub fn emu_register_handle_read(
    addr: SystemRegType,
    reg: usize,
    vcpu: Arc<AxVCpu<Aarch64VCpu>>,
) -> bool {
    let emu_reg = EMU_REGISTERS.read();
    for entry in emu_reg.iter() {
        if entry.addr == addr {
            return (entry.handle_read)(addr, reg, vcpu);
        }
    }
    panic!("Invalid emulated register read: addr={}", addr);
}

fn handle_write(
    addr: SystemRegType,
    _reg: usize,
    value: u64,
    _vcpu: Arc<AxVCpu<Aarch64VCpu>>,
) -> bool {
    info!(
        "write to emulated register: addr: {},  value: {:x}",
        addr, value
    );
    false
}
fn handle_read(addr: SystemRegType, _reg: usize, _vcpu: Arc<AxVCpu<Aarch64VCpu>>) -> bool {
    info!("read from emulated register: addr: {}", addr);
    false
}

lazy_static! {
    static ref EMU_REGISTERS: RwLock<Vec<EmuRegEntry>> = RwLock::new(vec![
        EmuRegEntry {
            emu_type: EmuRegType::SysReg,
            addr: SystemRegType::CNTPCT_EL0,
            handle_write: handle_write,
            handle_read: handle_read,
        },
        EmuRegEntry {
            emu_type: EmuRegType::SysReg,
            addr: SystemRegType::CNTP_TVAL_EL0,
            handle_write: handle_write,
            handle_read: handle_read,
        },
        EmuRegEntry {
            emu_type: EmuRegType::SysReg,
            addr: SystemRegType::CNTP_CTL_EL0,
            handle_write: handle_write,
            handle_read: handle_read,
        },
        EmuRegEntry {
            emu_type: EmuRegType::SysReg,
            addr: SystemRegType::CNTP_CVAL_EL0,
            handle_write: handle_write,
            handle_read: handle_read,
        },
    ]);
}
