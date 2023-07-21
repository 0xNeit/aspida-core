contract;

mod events;
mod structs;

use std::constants::ZERO_B256;
use std::assert::*;
use std::storage::*;

use events::*;
use structs::*;
use registry_abi::*;

pub enum ChargePeriod {
    Hourly: Hourly,
    Daily: Daily,
    Weekly: Weekly,
    Monthly: Monthly,
    Annually: Annually,
}

impl core::ops::Eq for ChargePeriod {
    fn eq(self, other: Self) -> bool {
        match (self, other) {
            (ChargePeriod::Hourly(hr1), ChargePeriod::Hourly(hr2)) => hr1 == hr2,
            (ChargePeriod::Daily(dy1), ChargePeriod::Daily(dy2)) => dy1 == dy2,
            (ChargePeriod::Weekly(wk1), ChargePeriod::Weekly(wk2)) => wk1 == wk2,
            (ChargePeriod::Monthly(mnth1), ChargePeriod::Monthly(mnth2)) => mnth1 == mnth2,
            (ChargePeriod::Annually(yr1), ChargePeriod::Annually(yr2)) => yr1 == yr2,
            _ => false,
        }
    }
}

storage {
    registry: ContractId =  ContractId { value: ZERO_B256 },
    risk_manager: ContractId = ContractId { value: ZERO_B256 },
    payment_manager: ContractId = ContractId { value: ZERO_B256 },
    paused: bool = false,
    base_uri: str[32] = "                                ",
    total_supply: u64 = 0,
    max_rate_num: u64 = 0,
    max_rate_denom: u64 = 0,
    charge_cycle: u64 = 0,
    latest_charged_time: u64 = 0,
    policy_of: StorageMap<Address, u64> = StorageMap {},
    cover_limit_of: StorageMap<u64, u64> = StorageMap {},
}

/***************************************
    INTERNAL FUNCTIONS
***************************************/

#[storage(read)]
fn while_unpaused() {
    assert(!storage.paused);
}

fn is_hourly(period: ChargePeriod) -> bool {
    match period {
        ChargePeriod::Hourly(_) => true,
        ChargePeriod::Daily(_) => false,
        ChargePeriod::Weekly(_) => false,
        ChargePeriod::Monthly(_) => false,
        ChargePeriod::Annually(_) => false,
    }
}

fn is_daily(period: ChargePeriod) -> bool {
    match period {
        ChargePeriod::Hourly(_) => false,
        ChargePeriod::Daily(_) => true,
        ChargePeriod::Weekly(_) => false,
        ChargePeriod::Monthly(_) => false,
        ChargePeriod::Annually(_) => false,
    }
}

fn is_weekly(period: ChargePeriod) -> bool {
    match period {
        ChargePeriod::Hourly(_) => false,
        ChargePeriod::Daily(_) => false,
        ChargePeriod::Weekly(_) => true,
        ChargePeriod::Monthly(_) => false,
        ChargePeriod::Annually(_) => false,
    }
}

fn is_monthly(period: ChargePeriod) -> bool {
    match period {
        ChargePeriod::Hourly(_) => false,
        ChargePeriod::Daily(_) => false,
        ChargePeriod::Weekly(_) => false,
        ChargePeriod::Monthly(_) => true,
        ChargePeriod::Annually(_) => false,
    }
}

fn is_annually(period: ChargePeriod) -> bool {
    match period {
        ChargePeriod::Hourly(_) => false,
        ChargePeriod::Daily(_) => false,
        ChargePeriod::Weekly(_) => false,
        ChargePeriod::Monthly(_) => false,
        ChargePeriod::Annually(_) => true,
    }
}

fn set_registry_internal(registry: ContractId) {
    // set registry
    assert(registry != ContractId::from(ZERO_B256));
    storage.registry = registry;

    // set risk manager
    let registry_abi = abi(Registry, registry.value);
    let (_, risk_manager_addr) = registry_abi.try_get("riskManager         ");
    assert(risk_manager_addr != ContractId::from(ZERO_B256));

    storage.risk_manager = risk_manager_addr;

    // set cover payment manager
    let (_, payment_manager_addr) = registry_abi.try_get("coverPaymentManager ");
    assert(payment_manager_addr != ContractId::from(ZERO_B256));
    storage.payment_manager = payment_manager_addr;

    log(
        RegistrySet {
            registry: registry,
        }
    );
}

fn get_charge_period_value(period: ChargePeriod) -> u64 {
    if (is_weekly(period) == true) {
        return 604800;
    } else if (is_monthly(period) == true) {
        return 2629746;
    } else if (is_annually(period) == true) {
        return 31556952;
    } else if (is_daily(period) == true) {
        return 86400;
    } else {
        // hourly
        return 3600;
    }
}

abi CoverProduct {
    fn test_function() -> bool;
}

impl CoverProduct for Contract {
    fn test_function() -> bool {
        true
    }
}
