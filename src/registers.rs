extern crate alloc;
use crate::vcpu::Aarch64VCpu;
use aarch64_cpu::registers::{Readable, Writeable};
use aarch64_cpu::registers::{CNTFRQ_EL0, CNTPCT_EL0, CNTP_CTL_EL0, CNTP_TVAL_EL0};
use alloc::sync::Arc;
use alloc::vec::Vec;
use axvcpu::{AxArchVCpu, AxVCpu};
use spin::RwLock;

/// Generates a system register address encoding based on the given operands and control register numbers.
/// This function uses bitwise operations to combine the parameters into a 32-bit address value.
///
/// # Arguments
/// * `op0` - The first operand, must be in the range 0 to 3.
/// * `op1` - The second operand, must be in the range 0 to 7.
/// * `crn` - The control register number (CRn), must be in the range 0 to 15.
/// * `crm` - The control register number (CRm), must be in the range 0 to 15.
/// * `op2` - The third operand, must be in the range 0 to 7.
///
/// # Returns
/// * A 32-bit address value representing the system register encoding.
///
/// # Example
/// ```
/// let addr = sysreg_enc_addr(1, 2, 3, 4, 5);
/// assert_eq!(addr, 0x10000000 | (5 << 17) | (2 << 14) | (3 << 10) | (4 << 1));
/// ```
#[inline(always)]
pub const fn sysreg_enc_addr(op0: usize, op1: usize, crn: usize, crm: usize, op2: usize) -> usize {
    (((op0) & 0x3) << 20)
        | (((op2) & 0x7) << 17)
        | (((op1) & 0x7) << 14)
        | (((crn) & 0xf) << 10)
        | (((crm) & 0xf) << 1)
}

const SYS_CNTFRQ_EL0: usize = sysreg_enc_addr(3, 3, 14, 0, 0);
const SYS_CNTPCT_EL0: usize = sysreg_enc_addr(3, 3, 14, 0, 1);
const SYS_CNTPCTSS_EL0: usize = sysreg_enc_addr(3, 3, 14, 0, 5);
const SYS_CNTVCTSS_EL0: usize = sysreg_enc_addr(3, 3, 14, 0, 6);

const SYS_CNTP_TVAL_EL0: usize = sysreg_enc_addr(3, 3, 14, 2, 0);
const SYS_CNTP_CTL_EL0: usize = sysreg_enc_addr(3, 3, 14, 2, 1);
const SYS_CNTP_CVAL_EL0: usize = sysreg_enc_addr(3, 3, 14, 2, 2);

const SYS_CNTV_TVAL_EL0: usize = sysreg_enc_addr(3, 3, 14, 3, 0);
const SYS_CNTV_CTL_EL0: usize = sysreg_enc_addr(3, 3, 14, 3, 1);
const SYS_CNTV_CVAL_EL0: usize = sysreg_enc_addr(3, 3, 14, 3, 2);
/// Struct representing an entry in the emulator register list.
pub struct EmuRegEntry {
    /// The type of the emulator register.
    pub emu_type: EmuRegType,
    /// The address associated with the emulator register.
    pub addr: usize,
    /// The handler write function for the emulator register.
    pub handle_write: fn(usize, usize, u64, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
    /// The handler read function for the emulator register.
    pub handle_read: fn(usize, usize, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
}

/// Enumeration representing the type of emulator registers.
pub enum EmuRegType {
    /// System register type for emulator registers.
    SysReg,
}

static EMU_REGISTERS: RwLock<Vec<EmuRegEntry>> = RwLock::new(Vec::new());

pub fn emu_register_add(
    addr: usize,
    handle_write: fn(usize, usize, u64, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
    handle_read: fn(usize, usize, Arc<AxVCpu<Aarch64VCpu>>) -> bool,
) {
    let mut emu_reg = EMU_REGISTERS.write();
    for entry in emu_reg.iter() {
        if entry.addr == addr {
            error!("Register:{:x} already exists", addr);
            return;
        }
    }
    info!("Register:{:x} added", addr);
    emu_reg.push(EmuRegEntry {
        emu_type: EmuRegType::SysReg,
        addr,
        handle_write,
        handle_read,
    });
}

pub fn emu_register_handle_write(
    addr: usize,
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
    panic!("Invalid emulated register write: addr=0x{:x}", addr);
}

pub fn emu_register_handle_read(addr: usize, reg: usize, vcpu: Arc<AxVCpu<Aarch64VCpu>>) -> bool {
    let emu_reg = EMU_REGISTERS.read();
    for entry in emu_reg.iter() {
        if entry.addr == addr {
            return (entry.handle_read)(addr, reg, vcpu);
        }
    }
    panic!("Invalid emulated register read: addr=0x{:x}", addr);
}

pub fn emu_register_init() {
    info!("emu_register_init");
    fn handle_write(addr: usize, reg: usize, value: u64, _vcpu: Arc<AxVCpu<Aarch64VCpu>>) -> bool {
        info!(
            "write to emulated register: addr: {:x},  value: {:x}",
            addr, value
        );
        false
    }
    fn handle_read(addr: usize, reg: usize, _vcpu: Arc<AxVCpu<Aarch64VCpu>>) -> bool {
        info!("read from emulated register: addr: {:x}", addr);
        false
    }
    emu_register_add(SYS_CNTPCT_EL0, handle_write, |addr, reg, vcpu| {
        // Get the current value of CNTPCT_EL0
        (*vcpu).set_gpr(reg, CNTPCT_EL0.get() as usize);
        true
    });
    emu_register_add(SYS_CNTFRQ_EL0, handle_write, handle_read);
    emu_register_add(SYS_CNTPCTSS_EL0, handle_write, handle_read);
    emu_register_add(SYS_CNTVCTSS_EL0, handle_write, handle_read);

    emu_register_add(
        SYS_CNTP_TVAL_EL0,
        |addr, reg, value, vcpu| {
            todo!("Set Timer Value");
            true
        },
        handle_read,
    );
    emu_register_add(SYS_CNTP_CTL_EL0, handle_write, handle_read);
    emu_register_add(SYS_CNTP_CVAL_EL0, handle_write, handle_read);

    emu_register_add(
        SYS_CNTV_TVAL_EL0,
        |addr, reg, value, vcpu| {
            todo!("Set Timer Value");
            true
        },
        handle_read,
    );
    emu_register_add(SYS_CNTV_CTL_EL0, handle_write, handle_read);
    emu_register_add(SYS_CNTV_CVAL_EL0, handle_write, handle_read);
}
