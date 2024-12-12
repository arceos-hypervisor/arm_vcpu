#![no_std]
#![feature(naked_functions)]
#![feature(doc_cfg)]
#![feature(asm_const)]
#![doc = include_str!("../README.md")]

#[macro_use]
extern crate log;

mod context_frame;
#[macro_use]
mod exception_utils;
mod exception;
mod pcpu;
mod system_registers;
mod vcpu;

pub use self::pcpu::Aarch64PerCpu;
pub use self::system_registers::Aarch64EmuRegs;
pub use self::vcpu::{Aarch64VCpu, Aarch64VCpuCreateConfig};

/// context frame for aarch64
pub type TrapFrame = context_frame::Aarch64ContextFrame;

/// Return if current platform support virtualization extension.
pub fn has_hardware_support() -> bool {
    // Hint:
    // In Cortex-A78, we can use
    // [ID_AA64MMFR1_EL1](https://developer.arm.com/documentation/101430/0102/Register-descriptions/AArch64-system-registers/ID-AA64MMFR1-EL1--AArch64-Memory-Model-Feature-Register-1--EL1)
    // to get whether Virtualization Host Extensions is supported.

    // Current just return true by default.
    true
}

/// Low-level resource interfaces that must be implemented by the crate user.
#[crate_interface::def_interface]
pub trait HalIf {
    fn irq_hanlder();
}
