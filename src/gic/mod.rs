extern crate alloc;

use core::result;

use alloc::{sync::Arc, vec, vec::Vec};
use arm_vgic::{v3::{gits::Gits, vgicd::VGicD, vgicr::VGicR}, vgic};
use axaddrspace::{GuestPhysAddr, HostPhysAddr};
use axdevice_base::BaseMmioDeviceOps;

/// Configuration for single virtual GICv3 Distributor. TODO: Move to `arm_vgic` crate.
#[derive(Debug, Clone)]
pub struct GicDistributorConfig {
    /// The base address of the GIC Distributor in guest physical address space.
    pub gicr_base: GuestPhysAddr,
    /// The ID of the CPU this GIC Distributor is associated with. FOR LOGGING PURPOSES ONLY.
    pub cpu_id: usize,
}

/// Configuration for single virtual GICv3 Distributor. TODO: Move to `arm_vgic` crate.
#[derive(Debug, Clone)]
pub struct GicSpiAssignment {
    /// The SPI number to assign.
    pub spi: u32,
    /// The CPU ID to assign the SPI to.
    pub target_cpu_phys_id: usize,
    /// The CPU affinity for the SPI, (aff3, aff2, aff1, aff0).
    pub target_cpu_affinity: (u8, u8, u8, u8),
}

/// GICv3 Device Configuration. TODO: Move to `arm_vgic` crate.
#[derive(Debug, Clone)]
pub struct GicDeviceConfig {
    pub gicd_base: GuestPhysAddr,
    pub gicrs: Vec<GicDistributorConfig>,
    pub assigned_spis: Vec<GicSpiAssignment>,
    pub gits_base: GuestPhysAddr,
    pub gits_phys_base: HostPhysAddr,
    pub is_root_vm: bool,
}

pub fn get_gic_devices(config: GicDeviceConfig) -> Vec<Arc<dyn BaseMmioDeviceOps>> {
    let mut results = Vec::<Arc<dyn BaseMmioDeviceOps>>::with_capacity(2 + config.gicrs.len());

    let mut gicd = VGicD::new(config.gicd_base, None);

    for assigned_spi in config.assigned_spis {
        gicd.assign_irq(assigned_spi.spi, assigned_spi.target_cpu_phys_id, assigned_spi.target_cpu_affinity);
    }

    results.push(Arc::new(gicd));

    for gicr in config.gicrs {
        results.push(Arc::new(VGicR::new(gicr.gicr_base, None, gicr.cpu_id)));
    }

    results.push(Arc::new(Gits::new(
        config.gits_base,
        None,
        config.gits_phys_base,
        config.is_root_vm,
    )));

    results


    // let mut vgicd = VGicD::new(0x0800_0000.into(), None);

    // vgicd.assigned_irqs.set(0x28, true);
    // // vgicd.assigned_irqs.set(0x1, true);


    // let vgicr0 = VGicR::new(0x080a_0000.into(), None, 0);
    // let vgicr1 = VGicR::new(0x080c_0000.into(), None, 1);
    // let vgicr2 = VGicR::new(0x080e_0000.into(), None, 2);

    // let gits = Gits::new(0x0808_0000.into(), None, 0x0808_0000.into(), true);

    // vec![
    //     Arc::new(vgicd),
    //     Arc::new(vgicr0),
    //     Arc::new(vgicr1),
    //     Arc::new(vgicr2),
    //     Arc::new(gits),
    // ]
}
