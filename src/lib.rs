#![no_std]
#![cfg(target_arch = "aarch64")]
#![feature(doc_cfg)]
#![doc = include_str!("../README.md")]

#[macro_use]
extern crate log;

#[macro_use]
extern crate alloc;

mod context_frame;
#[macro_use]
mod exception_utils;
mod exception;
mod exit;
mod pcpu;
mod smc;
mod vcpu;

use core::sync::atomic::{AtomicBool, Ordering};

pub use self::pcpu::Aarch64PerCpu;
pub use self::vcpu::{Aarch64VCpu, Aarch64VCpuCreateConfig, Aarch64VCpuSetupConfig};
use alloc::vec::Vec;
pub use axvm_types::addr::*;
pub use axvm_types::device::*;
pub use exit::*;

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

pub trait CpuHal {
    fn irq_hanlder(&self);
    fn inject_interrupt(&self, irq: usize);
    /// Cpu hard id list
    fn cpu_list(&self) -> Vec<usize>;
}

struct NopHal;

impl CpuHal for NopHal {
    fn irq_hanlder(&self) {
        unimplemented!()
    }
    fn inject_interrupt(&self, _irq: usize) {
        unimplemented!()
    }

    fn cpu_list(&self) -> Vec<usize> {
        unimplemented!()
    }
}

static mut HAL: &dyn CpuHal = &NopHal;
static INIT: AtomicBool = AtomicBool::new(false);

fn hal() -> &'static dyn CpuHal {
    unsafe { HAL }
}

fn handle_irq() {
    hal().irq_hanlder();
}

fn inject_interrupt(irq: usize) {
    hal().inject_interrupt(irq);
}

pub fn init_hal(hal: &'static dyn CpuHal) {
    if INIT
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
        unsafe {
            HAL = hal;
        }
    } else {
        panic!("arm_vcpu hal has been initialized");
    }

    unsafe { vcpu::init_host_sp_el0() };
}
