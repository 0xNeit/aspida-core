contract;

mod events;

use std::constants::ZERO_B256;
use std::assert::*;
use std::auth::*;
use std::storage::*;
use std::call_frames::*;
use std::b512::B512;
use std::block::*;

use events::*;
use registry_abi::*;
use cpm_abi::*;
use cover_product_abi::*;
use cover_product_abi::structs::*;
use executor_abi::*;
use risk_manager_abi::*;

use reentrancy::*;

use nft::{
    approved,
    is_approved_for_all,
    mint,
    owner_of,
    tokens_minted,
};

use nft::extensions::burnable::*;

use nft::extensions::token_metadata::*;

pub struct ProductMeta {
    name: str[26],
    symbol: str[3],
}

impl ProductMeta {
    pub fn new() -> Self {
        Self {
            name: "Aspida Portfolio Insurance",
            symbol: "API",
        }
    }
}

storage {
    owner: Address = Address { value: ZERO_B256 },
    registry: ContractId =  ContractId { value: ZERO_B256 },
    risk_manager: ContractId = ContractId { value: ZERO_B256 },
    payment_manager: ContractId = ContractId { value: ZERO_B256 },
    paused: bool = false,
    total_supply: u64 = 0,
    max_rate_num: u64 = 0,
    max_rate_denom: u64 = 0,
    charge_cycle: u64 = 0,
    latest_charged_time: u64 = 0,
    policy_of: StorageMap<Identity, u64> = StorageMap {},
    cover_limit_of: StorageMap<u64, u64> = StorageMap {},
    executor: ContractId = ContractId { value: ZERO_B256 },
}

/***************************************
    INTERNAL fnS
***************************************/

fn as_contract_id(to: Identity) -> Option<ContractId> {
    match to {
        Identity::Address(_) => Option::None,
        Identity::ContractId(id) => Option::Some(id),
    }
}

fn as_address(to: Identity) -> Option<Address> {
    match to {
        Identity::Address(addr) => Option::Some(addr),
        Identity::ContractId(_) => Option::None,
    }
}

#[storage(read)]
fn while_unpaused() {
    assert(!storage.paused);
}

#[storage(read)]
fn only_collector() {
    let sender = msg_sender().unwrap();
    assert(
        sender == abi(Registry, storage.registry.value).get("premiumCollector    ") ||
        sender == Identity::Address(storage.owner)
    );
}

/*fn is_hourly(period: ChargePeriod) -> bool {
    match period {
        ChargePeriod::Hourly(_) => true,
        ChargePeriod::Daily(_) => false,
        ChargePeriod::Weekly(_) => false,
        ChargePeriod::Monthly(_) => false,
        ChargePeriod::Annually(_) => false,
    }
}*/

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

pub fn get_msg_sender_address_or_panic() -> Address {
    let sender: Result<Identity, AuthError> = msg_sender();
    if let Identity::Address(address) = sender.unwrap() {
        address
    } else {
        revert(0);
    }
}

#[storage(read)]
fn validate_owner() {
    let sender = get_msg_sender_address_or_panic();
    assert(storage.owner == sender);
}

#[storage(read)]
fn policy_status(policy_id: u64) -> bool {
    if (storage.cover_limit_of.get(policy_id).unwrap() > 0) {
        return true;
    } else {
        return false;
    }
}

#[storage(read)]
fn min_required_account_balance(cover_limit: u64) -> u64 {
    let max_rate_num = storage.max_rate_num;
    let charge_cycle = storage.charge_cycle;
    let max_rate_denom = storage.max_rate_denom;
    let result = (max_rate_num * charge_cycle * cover_limit) / max_rate_denom;
    return result;
}

#[storage(read)]
fn min_acp_required_internal(policy_holder: Identity) -> u64 {
    let policy = storage.policy_of.get(policy_holder).unwrap();
    if (policy_status(policy)) {
        return min_required_account_balance(storage.cover_limit_of.get(policy).unwrap());
    }
    return 0;
} 

#[storage(read)]
fn get_acp_balance(account: Identity) -> u64 {
    return abi(CoverPaymentManager, storage.payment_manager.value).get_acp_balance(account);
}

#[storage(read)]
fn max_cover() -> u64 {
    let mc = abi(RiskManager, storage.risk_manager.value).max_cover_per_strategy(contract_id());
    return mc;
}

#[storage(read)]
fn active_cover_limit() -> u64 {
    let mcl = abi(RiskManager, storage.risk_manager.value).active_cover_limit_per_strategy(contract_id());
    return mcl;
}

#[storage(read)]
fn available_cover_capacity() -> u64 {
    let capacity = max_cover() - active_cover_limit();
    return capacity;
}

#[storage(read)]
fn check_capacity(current_cover_limit: u64, new_cover_limit: u64) -> bool {
    // return true if user is lowering cover limit
    if (new_cover_limit <= current_cover_limit) {
        return true;
    };
    // check capacity
    let diff = new_cover_limit - current_cover_limit;
    if (diff < available_cover_capacity()) {
        return true;
    };

    // no available capacity
    return false;
}

#[storage(read, write)]
fn purchase_internal(user: Identity, cover_limit: u64) -> u64 {
    let mut policy_id = storage.policy_of.get(user).unwrap();

    // mint policy if doesn't exist
    let mint_bool: bool = policy_id == 0;
    if (mint_bool) {
        policy_id = storage.total_supply + 1;
        storage.policy_of.insert(user, policy_id);
        
        mint(1, user);

        set_token_metadata(Option::Some(ProductMeta::new()), policy_id);

        log(
            PolicyCreated {
                policy_id: policy_id
            }
        );
    }

    let sender = msg_sender().unwrap();

    // only update cover limit if initial mint or called by policyholder
    if (mint_bool || sender == user) {
        let current_cover_limit = storage.cover_limit_of.get(policy_id).unwrap();
        if(cover_limit != current_cover_limit) {
            assert(check_capacity(current_cover_limit, cover_limit));
            // update cover amount
            update_active_cover_limit_internal(current_cover_limit, cover_limit);
            storage.cover_limit_of.insert(policy_id, cover_limit);
        };

        let cpm = get_acp_balance(user);

        assert(cpm >= min_required_account_balance(cover_limit));
        
        log(
            PolicyUpdated {
                policy_id: policy_id
            }
        );
    }

    return policy_id;
}

#[storage(read, write)]
fn purchase_with_stable_internal(
    purchaser: Identity, 
    user: Identity, 
    cover_limit: u64, 
    token: ContractId, 
    amount: u64
) -> u64 {
    abi(CoverPaymentManager, storage.payment_manager.value).deposit_stable_from(token, purchaser, user, amount);
    return purchase_internal(user, cover_limit);
}

#[storage(read, write)]
fn purchase_with_non_stable_internal(
    purchaser: Identity,
    user: Identity,
    cover_limit: u64,
    token: ContractId,
    amount: u64,
    price: u64,
    price_deadline: u64,
    signature: B512
) -> u64 {
    abi(CoverPaymentManager, storage.payment_manager.value).deposit_non_stable_from(token, purchaser, user, amount, price, price_deadline, signature);
    return purchase_internal(user, cover_limit);
}

#[storage(read)]
fn update_active_cover_limit_internal(current_cover_limit: u64, new_cover_limit: u64) {
    abi(RiskManager, storage.risk_manager.value).update_active_cover_limit_for_strategy(contract_id(), current_cover_limit, new_cover_limit);
} 

#[storage(write)]
fn set_registry_internal(registry: ContractId) {
    // set registry
    assert(registry != ContractId::from(ZERO_B256));
    storage.registry = registry;

    // set risk manager
    let registry_abi = abi(Registry, registry.value);
    let (_, risk_manager_addr) = registry_abi.try_get("riskManager         ");
    assert(risk_manager_addr != Identity::ContractId(ContractId::from(ZERO_B256)));

    storage.risk_manager = as_contract_id(risk_manager_addr).unwrap();

    // set cover payment manager
    let (_, payment_manager_addr) = registry_abi.try_get("coverPaymentManager ");
    assert(payment_manager_addr != Identity::ContractId(ContractId::from(ZERO_B256)));
    storage.payment_manager = as_contract_id(payment_manager_addr).unwrap();

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

impl CoverProduct for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId) {
        set_registry_internal(registry);

        let mut mrn = storage.max_rate_num;
        let mut mrd = storage.max_rate_denom;
        let mut charge_cycle = storage.charge_cycle;
        let mut owner_store = storage.owner;

        mrn = 1;
        mrd = 315360000;
        charge_cycle = get_charge_period_value(ChargePeriod::Weekly(Weekly::new()));
        owner_store = owner;

        storage.max_rate_num = mrn;
        storage.max_rate_denom = mrd;
        storage.charge_cycle = charge_cycle;
        storage.owner = owner_store;
    }

    #[storage(read)]
    fn min_acp_required(policy_holder: Identity) -> u64 {
        return min_acp_required_internal(policy_holder);
    }

    #[storage(read)]
    fn update_active_cover_limit(current_cover_limit: u64, new_cover_limit: u64) {
        update_active_cover_limit_internal(current_cover_limit, new_cover_limit);
    }

    /***************************************
    POLICY fnS
    ***************************************/

    #[storage(read, write)]
    fn purchase(user: Identity, cover_limit: u64)  {
        reentrancy_guard();
        while_unpaused();

        let _ = purchase_internal(user, cover_limit);
    }

    #[storage(read, write)]
    fn purchase_with_stable(
        user: Identity,
        cover_limit: u64,
        token: ContractId,
        amount: u64
    ) -> u64 {
        reentrancy_guard();
        while_unpaused();

        let sender = msg_sender().unwrap();

        return purchase_with_stable_internal(sender, user, cover_limit, token, amount);
    }

    #[storage(read, write)]
    fn purchase_with_non_stable(
        user: Identity,
        cover_limit: u64,
        token: ContractId,
        amount: u64,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) -> u64 {
        reentrancy_guard();
        while_unpaused();

        let sender = msg_sender().unwrap();

        return purchase_with_non_stable_internal(sender, user, cover_limit, token, amount, price, price_deadline, signature);
    }

    #[storage(read, write)]
    fn cancel(premium: u64, deadline: u64, signature: B512) {
        let sender = msg_sender().unwrap();

        assert(policy_status(storage.policy_of.get(sender).unwrap()));
        assert(abi(Executor, storage.executor.value).verify_premium(premium, as_address(sender).unwrap(), deadline, signature));

        let acp_balance = get_acp_balance(sender);
        let mut charge_amount = 0;
        if (acp_balance < premium) {
            charge_amount = acp_balance;
        } else {
            charge_amount = premium;
        };

        if (charge_amount > 0) {
            let mut accounts: Vec<Identity> = Vec::new();
            let mut premiums: Vec<u64> = Vec::new();

            accounts.push(sender);
            premiums.push(charge_amount);

            abi(CoverPaymentManager, storage.payment_manager.value).charge_premiums(accounts, premiums);
        };

        let policy_id = storage.policy_of.get(sender).unwrap();
        let cover_limit = storage.cover_limit_of.get(policy_id).unwrap();

        update_active_cover_limit_internal(cover_limit, 0);
        storage.cover_limit_of.insert(policy_id, 0);

        log(
            PolicyCanceled {
                policy_id: policy_id,
            }
        );
    }

    #[storage(read, write)]
    fn cancel_policies(policy_holders: Vec<Identity>) {
        only_collector();
        let count = policy_holders.len();
        // let policyholder;
        let mut policy_id = 0;
        let mut cover_limit = 0;
        let mut i = 0;

        while (i < count) {
            let policy_holder = policy_holders.get(i).unwrap();
            policy_id = storage.policy_of.get(policy_holder).unwrap();

            if (policy_status(policy_id)) {
                cover_limit = storage.cover_limit_of.get(policy_id).unwrap();
                update_active_cover_limit_internal(cover_limit, 0);
                storage.cover_limit_of.insert(policy_id, 0);
                
                log(
                    PolicyCanceled {
                        policy_id: policy_id
                    }
                );
            };

            i = i + 1;
        }
    }

    /***************************************
    GOVERNANCE fnS
    ***************************************/

    #[storage(read, write)]
    fn set_registry(registry: ContractId) {
        validate_owner();
        set_registry_internal(registry);
    }

    #[storage(read, write)]
    fn set_paused(paused: bool) {
        validate_owner();
        let mut paused_state = storage.paused;
        paused_state = paused;
        storage.paused = paused_state;

        log(
            PauseSet {
                pause: paused
            }
        );
    }

    #[storage(read, write)]
    fn set_max_rate(max_rate_num: u64, max_rate_denom: u64) {
        validate_owner();
        let mut mrn = storage.max_rate_num;
        mrn = max_rate_num;
        storage.max_rate_num = mrn;

        let mut mrd = storage.max_rate_denom;
        mrd = max_rate_denom;
        storage.max_rate_denom = mrd;

        log(
            MaxRateSet {
                max_rate_num: max_rate_num,
                max_rate_denom: max_rate_denom,
            }
        );
    }

    #[storage(read, write)]
    fn set_charge_cycle(charge_cycle: ChargePeriod) {
        validate_owner();
        let mut cc = storage.charge_cycle;
        cc = get_charge_period_value(charge_cycle);
        storage.charge_cycle = cc;

        log(
            ChargeCycleSet {
                charge_cycle: cc,
            }
        );
    }

    /***************************************
    PREMIUM COLLECTOR fnS
    ***************************************/

    #[storage(read, write)]
    fn set_charged_time(time: u64) {
        while_unpaused();
        only_collector();

        assert(time > 0 && time <= timestamp());
        let mut time_store = storage.latest_charged_time;
        time_store = time;
        storage.latest_charged_time = time_store;

        log(
            LatestChargedTimeSet {
                timestamp: time
            }
        );
    }
}
