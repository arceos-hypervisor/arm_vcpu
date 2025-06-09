extern crate alloc;

use alloc::{sync::Arc, vec, vec::Vec};
use arm_vgic::v3::{vgicd::VGicD, vgicr::VGicR};
use axdevice_base::BaseMmioDeviceOps;

pub fn get_gic_devices() -> Vec<Arc<dyn BaseMmioDeviceOps>> {
    let vgicd = VGicD::new(0x0800_0000.into(), None);

    let vgicr0 = VGicR::new(0x080a_0000.into(), None, 0);
    let vgicr1 = VGicR::new(0x080c_0000.into(), None, 1);
    let vgicr2 = VGicR::new(0x080e_0000.into(), None, 2);

    vec![
        Arc::new(vgicd),
        Arc::new(vgicr0),
        Arc::new(vgicr1),
        Arc::new(vgicr2),
    ]
}
