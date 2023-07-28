library;

mod structs;

use structs::*;

use std::b512::B512;

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

abi CoverProduct {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId);

    #[storage(read)]
    fn min_acp_required(policy_holder: Identity) -> u64;

    #[storage(read)]
    fn update_active_cover_limit(current_cover_limit: u64, new_cover_limit: u64);

    #[storage(read, write)]
    fn purchase(user: Identity, cover_limit: u64);

    #[storage(read, write)]
    fn purchase_with_stable(
        user: Identity,
        cover_limit: u64,
        token: ContractId,
        amount: u64
    ) -> u64;

    #[storage(read, write)]
    fn purchase_with_non_stable(
        user: Identity,
        cover_limit: u64,
        token: ContractId,
        amount: u64,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) -> u64;

    #[storage(read, write)]
    fn cancel(premium: u64, deadline: u64, signature: B512);

    #[storage(read, write)]
    fn cancel_policies(policy_holders: Vec<Identity>);

    #[storage(read, write)]
    fn set_registry(registry: ContractId);

    #[storage(read, write)]
    fn set_paused(paused: bool);

    #[storage(read, write)]
    fn set_max_rate(max_rate_num: u64, max_rate_denom: u64);

    #[storage(read, write)]
    fn set_charge_cycle(charge_cycle: ChargePeriod);

    #[storage(read, write)]
    fn set_charged_time(timestamp: u64);
}
