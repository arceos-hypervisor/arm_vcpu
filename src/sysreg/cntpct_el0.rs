use aarch64_sysreg::SystemRegType;

use aarch64_cpu::registers::{CNTPCT_EL0, Readable};

use axaddrspace::{
    GuestPhysAddrRange,
    device::{AccessWidth, DeviceAddrRange, SysRegAddr, SysRegAddrRange},
};

use axdevice_base::{BaseDeviceOps, EmuDeviceType};

use axerrno::AxResult;

impl BaseDeviceOps<SysRegAddrRange> for SysCntpctEl0 {
    fn emu_type(&self) -> EmuDeviceType {
        EmuDeviceType::EmuDeviceTConsole
    }

    fn address_range(&self) -> SysRegAddrRange {
        SysRegAddrRange {
            start: SysRegAddr::new(SystemRegType::CNTPCT_EL0 as usize),
            end: SysRegAddr::new(SystemRegType::CNTPCT_EL0 as usize),
        }
    }

    fn handle_read(
        &self,
        addr: <SysRegAddrRange as DeviceAddrRange>::Addr,
        width: AccessWidth,
    ) -> AxResult<usize> {
        Ok(CNTPCT_EL0.get() as usize)
    }

    fn handle_write(
        &self,
        addr: <SysRegAddrRange as DeviceAddrRange>::Addr,
        width: AccessWidth,
        val: usize,
    ) -> AxResult {
        info!("Write to emulator register: {:?}, value: {}", addr, val);
        Ok(())
    }
}

pub struct SysCntpctEl0 {
    // Fields
}

impl SysCntpctEl0 {
    pub fn new() -> Self {
        Self {
            // Initialize fields
        }
    }
}
