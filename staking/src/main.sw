contract;

mod events;

use std::constants::ZERO_B256;
use std::assert::*;
use std::block::*;
use std::call_frames::contract_id;
use std::auth::*;
use std::b512::B512;

use registry_abi::Registry;
use locker_abi::{ Lock, Locker };
use token_abi::*;
use staking_abi::*;
use cpm_abi::*;
use events::*;
use nft::{
    owner_of,
};

use reentrancy::*;

storage {
    owner: Address = Address {
        value: ZERO_B256,
    },
    registry: ContractId = ContractId {
        value: ZERO_B256,
    },                                                  // The registry address.
    cover_payment_manager: ContractId = ContractId {
        value: ZERO_B256,
    },                                                  // The cover payment manager address.
    pida: ContractId = ContractId {
        value: ZERO_B256,
    },                                                  // The PIDA Token contract address
    xp_locker: ContractId = ContractId {
        value: ZERO_B256,
    },                                                  // The xp_locker contract.
    reward_per_second: u64 = 0,                         // Amount of PIDA distributed per second.
    start_time: u64 = 0,                                // When the farm will start.
    end_time: u64 = 0,                                  // When the farm will end.
    last_reward_time: u64 = 0,                          // Last time rewards were distributed or farm was updated.
    acc_reward_per_share: u64 = 0,                      // Accumulated rewards per share, times 1e12.
    value_staked: u64 = 0,                              // Value of tokens staked by all farmers.

    lock_info: StorageMap<u64, StakedLockInfo> = StorageMap {},
    // was_lock_migrated: StorageMap<u64, bool> = StorageMap {}, 
}

/// The maximum duration of a lock in seconds.
const MAX_LOCK_DURATION: u64 = 126_144_000;

/// The vote power multiplier at max lock in bps.
const MAX_LOCK_MULTIPLIER_BPS: u64 = 25000;  // 2.5X

/// The vote power multiplier when unlocked in bps.
const UNLOCKED_MULTIPLIER_BPS: u64 = 10000; // 1X

// 1 bps = 1/10000
const MAX_BPS: u64 = 10000;

// multiplier to increase precision
const Q12: u64 = 1_000_000_000_000;

fn as_contract_id(to: Identity) -> Option<ContractId> {
    match to {
        Identity::Address(_) => Option::None,
        Identity::ContractId(id) => Option::Some(id),
    }
}


#[storage(read, write)]
fn set_registry_internal(registry: ContractId) {
    assert(registry != ContractId::from(ZERO_B256));
    let mut reg = storage.registry;
    reg = registry;
    storage.registry = reg;

    let mut cpm = storage.cover_payment_manager;
    let mut pida = storage.pida;
    let mut xplocker = storage.xp_locker;

    let new_reg = abi(Registry, storage.registry.value);

    // set pcp
    let (_, cpm_addr) = new_reg.try_get("coverPaymentManager ");
    assert(cpm_addr != Identity::ContractId(ContractId::from(ZERO_B256)));
    cpm = as_contract_id(cpm_addr).unwrap();
    storage.cover_payment_manager = cpm;

    // set pida
    let (_, pida_addr) = new_reg.try_get("pida                ");
    assert(pida_addr != Identity::ContractId(ContractId::from(ZERO_B256)));
    pida = as_contract_id(pida_addr).unwrap();
    storage.pida = pida;

    // set xplocker
    let (_, xp_locker_addr) = new_reg.try_get("xpLocker            ");
    assert(xp_locker_addr != Identity::ContractId(ContractId::from(ZERO_B256)));
    xplocker = as_contract_id(xp_locker_addr).unwrap();
    storage.xp_locker = xplocker;

    log(
        RegistrySet {
            registry: registry,
        }
    );
}

fn max(a: u64, b: u64) -> u64 {
    let mut answer: u64 = 0;
    if (a > b) {
        answer = a;
    } else {
        answer = b;
    }

    answer
}

fn min(a: u64, b: u64) -> u64 {
    let mut answer: u64 = 0;
    if (a < b) {
        answer = a;
    } else {
        answer = b;
    }

    answer
}


#[storage(read)]
fn get_reward_amount_distributed(from: u64, to: u64) -> u64 {
    // validate window
    let new_from = max(from, storage.start_time);
    let new_to = min(to, storage.end_time);
    // no reward for negative window
    if (new_from > new_to) {
        return 0;
    };

    return (to - from) * storage.reward_per_second;
}

fn as_address(to: Identity) -> Option<Address> {
    match to {
        Identity::Address(addr) => Option::Some(addr),
        Identity::ContractId(_) => Option::None,
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
fn fetch_lock_info(xp_lock_id: u64) -> (bool, Address, Lock) {
    let locker = abi(Locker, storage.xp_locker.value);
    let exists = locker.exists(xp_lock_id);
    let mut owner = Address {
        value: ZERO_B256,
    };

    let mut lock = Lock {
        amount: 0,
        end: 0,
    };

    if (exists) {
        owner = as_address(owner_of(xp_lock_id).unwrap()).unwrap();
        lock = locker.locks(xp_lock_id);
    } else {
        owner = Address::from(ZERO_B256);
        lock = Lock {
            amount: 0,
            end: 0,
        };
    }

    return (exists, owner, lock);
}

#[storage(read)]
fn calculate_lock_value(amount: u64, end: u64) -> u64 {
    let base = amount * UNLOCKED_MULTIPLIER_BPS / MAX_BPS;
    let mut bonus = 0;
    if (end <= timestamp()) {
        bonus = 0;
    } else {
        bonus = amount * (end - timestamp()) * (MAX_LOCK_MULTIPLIER_BPS - UNLOCKED_MULTIPLIER_BPS) / (MAX_LOCK_DURATION * MAX_BPS);
    };
    
    return base + bonus;
}

#[storage(read, write)]
fn update_lock(xp_lock_id: u64) -> (u64, Address) {
    // math
    let acc_reward_per_share = storage.acc_reward_per_share;
    // get lock information
    let mut lock_info = storage.lock_info.get(xp_lock_id).unwrap();
    let (exists, owner, lock) = fetch_lock_info(xp_lock_id);
    // accumulate and transfer unpaid rewards
    let mut transfer_amount = 0;
    lock_info.unpaid_rewards += lock_info.value * acc_reward_per_share / Q12 - lock_info.reward_debt;
    if (lock_info.owner != Address::from(ZERO_B256)) {
        let pida_abi = abi(FRC20, storage.pida.value);
        let balance = pida_abi.balance_of(Identity::ContractId(contract_id()));
        transfer_amount = min(lock_info.unpaid_rewards, balance);
        lock_info.unpaid_rewards -= transfer_amount;
    };
    // update lock value
    let old_value = lock_info.value;
    let new_value = calculate_lock_value(lock.amount, lock.end);
    lock_info.value = new_value;
    lock_info.reward_debt = new_value * acc_reward_per_share / Q12;
    if (old_value != new_value) {
        let mut staked_value = storage.value_staked;
        staked_value = staked_value - old_value + new_value;
    };
    // update lock owner. maintain pre-burn owner in case of unpaid rewards
    if (owner != lock_info.owner && exists) {
        lock_info.owner = owner;
    };
    let _ = storage.lock_info.remove(xp_lock_id);
    storage.lock_info.insert(xp_lock_id, lock_info);
    
    log(
        LockUpdated {
            xp_lock_id: xp_lock_id,
        }
    );

    let mut receiver = Address {
        value: ZERO_B256,
    };

    if (lock_info.owner == Address::from(ZERO_B256)) {
        receiver = owner;
    } else {
        receiver = lock_info.owner;
    };
    
    return (transfer_amount, receiver);
}

#[storage(read, write)]
fn harvest_internal(xp_lock_id: u64) {
    let (transfer_amount, receiver) = update_lock(xp_lock_id);
    if ( receiver != Address::from(ZERO_B256) && transfer_amount != 0) {
        let pida_abi = abi(FRC20, storage.pida.value);
        pida_abi.transfer(transfer_amount, receiver);
    }
}

#[storage(read, write)]
fn harvest_for_acp_internal(
    xp_lock_id: u64,
    price: u64,
    price_deadline: u64,
    signature: B512,
) {
    let sender = msg_sender().unwrap();
    let (transfer_amount, owner) = update_lock(xp_lock_id);
    assert(as_address(sender).unwrap() == owner);
    // buy acp
    if (owner != Address::from(ZERO_B256) && transfer_amount != 0) {
        abi(CoverPaymentManager, storage.cover_payment_manager.value).deposit_non_stable(
            storage.pida, 
            Identity::Address(owner), 
            transfer_amount, 
            price, 
            price_deadline, 
            signature
        );
    }
}

#[storage(read, write)]
fn update() {
    if (timestamp() <= storage.last_reward_time) {
        return;
    };

    if (storage.value_staked == 0) {
        storage.last_reward_time = min(timestamp(), storage.end_time);
        return;
    }

    let token_reward = get_reward_amount_distributed(storage.last_reward_time, timestamp());
    storage.acc_reward_per_share += token_reward * Q12 / storage.value_staked;
    storage.last_reward_time = min(timestamp(), storage.end_time);
}

impl Staking for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;

        set_registry_internal(registry);

    }

    /// Information about each lock.
    /// lock id => lock info
    #[storage(read)]
    fn staked_lock_info(xp_lock_id: u64) -> StakedLockInfo {
        let lock_info = storage.lock_info.get(xp_lock_id).unwrap();
        lock_info
    }

    
    #[storage(read)]
    fn pending_rewards_of_lock(xp_lock_id: u64) -> u64 {
        // get lock information
        let lock_info = storage.lock_info.get(xp_lock_id).unwrap();
        // math
        let mut acc_reward_per_share = storage.acc_reward_per_share;
        if (timestamp() > storage.last_reward_time && storage.value_staked != 0) {
            let token_reward = get_reward_amount_distributed(storage.last_reward_time, timestamp());
            acc_reward_per_share += token_reward * Q12 / storage.value_staked;
        }
        return lock_info.value * acc_reward_per_share / Q12 - lock_info.reward_debt + lock_info.unpaid_rewards;
    }

    #[storage(read, write)]
    fn register_lock_event(
        xp_lock_id: u64,
        old_owner: Address,
        new_owner: Address,
        old_lock: Lock,
        new_lock: Lock,
    ) {
        reentrancy_guard();
        update();
        harvest_internal(xp_lock_id);

        log(
            LockEvent {
                xp_lock_id: xp_lock_id,
                old_owner: old_owner,
                new_owner: new_owner,
                old_lock: old_lock,
                new_lock: new_lock,
            }
        );
    }

    #[storage(read, write)]
    fn harvest_lock(xp_lock_id: u64) {
        reentrancy_guard();
        update();
        harvest_internal(xp_lock_id);
    }

    #[storage(read, write)]
    fn harvest_locks(xp_lock_ids: Vec<u64>) {
        reentrancy_guard();
        update();
        let len = xp_lock_ids.len();
        let mut i = 0;
        while (i < len) {
            harvest_internal(xp_lock_ids.get(i).unwrap());
            i = i + 1;
        }
    }

    #[storage(read, write)]
    fn compound_lock(xp_lock_id: u64) {
        let sender = msg_sender().unwrap();
        let locker = abi(Locker, storage.xp_locker.value);
        assert(sender == owner_of(xp_lock_id).unwrap());
        update();
        let (transfer_amount, _) = update_lock(xp_lock_id);

        if (transfer_amount != 0) {
            locker.increase_amount(xp_lock_id, transfer_amount);
        }
    }

    #[storage(read, write)]
    fn compound_locks(xp_lock_ids: Vec<u64>, increased_lock_id: u64) {
        update();
        let sender = msg_sender().unwrap();
        let locker = abi(Locker, storage.xp_locker.value);
        let len = xp_lock_ids.len();
        let mut transfer_amount = 0;
        let mut i = 0;
        while (i < len) {
            let xp_lock_id = xp_lock_ids.get(i).unwrap();
            assert(sender == owner_of(xp_lock_id).unwrap());
            let (ta, _) = update_lock(xp_lock_id);
            transfer_amount += ta;
            i = 1 + 1;
        };

        if (transfer_amount != 0) {
            locker.increase_amount(increased_lock_id, transfer_amount);
        };
    }

    #[storage(read, write)]
    fn harvest_lock_for_acp(
        xp_lock_id: u64,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) {
        reentrancy_guard();
        update();
        harvest_for_acp_internal(xp_lock_id, price, price_deadline, signature);
    }

    #[storage(read, write)]
    fn harvest_locks_for_acp(
        xp_lock_ids: Vec<u64>, 
        price: u64, 
        price_deadline: u64, 
        signature: B512,
    ) {
        reentrancy_guard();
        update();
        let len = xp_lock_ids.len();
        let mut i = 0;
        while (i < len) {
            harvest_for_acp_internal(
                xp_lock_ids.get(i).unwrap(), 
                price, 
                price_deadline, 
                signature
            );

            i = i + 1;
        }
    }

    #[storage(read, write)]
    fn set_rewards(reward_per_second: u64) {
        validate_owner();
        update();

        let mut reward_store = storage.reward_per_second;
        reward_store = reward_per_second;
        storage.reward_per_second = reward_store;

        log(
            RewardsSet {
                reward_per_second: reward_per_second
            }
        );
    }

    #[storage(read, write)]
    fn set_times(start_time: u64, end_time: u64) {
        validate_owner();

        assert(start_time <= end_time);

        let mut st = storage.start_time;
        st = start_time;
        storage.start_time = st;

        let mut et = storage.end_time;
        et = end_time;
        storage.end_time = et;

        log(
            FarmTimesSet {
                start_time: start_time,
                end_time: end_time
            }
        );

        update();
    }

    #[storage(read, write)]
    fn set_registry(registry: ContractId) {
        validate_owner();

        set_registry_internal(registry);
    }

}
