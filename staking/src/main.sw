contract;

mod events;

use std::constants::ZERO_B256;
use std::assert::*;
use std::block::*;

use registry_abi::Registry;
use events::*;

// Info of each lock.
pub struct StakedLockInfo {
    value: u64,             // Value of user provided tokens.
    reward_debt: u64,       // Reward debt. See explanation below.
    unpaid_rewards: u64,    // Rewards that have not been paid.
    owner: Address,         // Account that owns the lock.
    //
    // We do some fancy math here. Basically, any point in time, the amount of reward token
    // entitled to the owner of a lock but is pending to be distributed is:
    //
    //   pending reward = (lock_info.value * accRewardPerShare) - lock_info.rewardDebt + lock_info.unpaidRewards
    //
    // Whenever a user updates a lock, here's what happens:
    //   1. The farm's `acc_reward_per_share` and `last_reward_time` gets updated.
    //   2. Users pending rewards accumulate in `unpaid_rewards`.
    //   3. User's `value` gets updated.
    //   4. User's `reward_debt` gets updated.
}

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
    was_lock_migrated: StorageMap<u64, bool> = StorageMap {}, 
}

/// @notice The maximum duration of a lock in seconds.
const MAX_LOCK_DURATION: u64 = 126_144_000;

/// @notice The vote power multiplier at max lock in bps.
const MAX_LOCK_MULTIPLIER_BPS: u64 = 25000;  // 2.5X

/// @notice The vote power multiplier when unlocked in bps.
const UNLOCKED_MULTIPLIER_BPS: u64 = 10000; // 1X

// 1 bps = 1/10000
const MAX_BPS: u64 = 10000;

// multiplier to increase precision
const Q12: u64 = 1_000_000_000_000;

/**
    * @notice Sets registry and related contract addresses.
    * @param _registry The registry address to set.
*/
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
    let (_, cpm_addr) = new_reg.tryGet("coverPaymentManager ");
    assert(cpm_addr != ContractId::from(ZERO_B256));
    cpm = cpm_addr;
    storage.cover_payment_manager = cpm;

    // set pida
    let (_, pida_addr) = new_reg.tryGet("pida                ");
    assert(pida_addr != ContractId::from(ZERO_B256));
    pida = pida_addr;
    storage.pida = pida;

    // set xplocker
    let (_, xp_locker_addr) = new_reg.tryGet("xpLocker            ");
    assert(xp_locker_addr != ContractId::from(ZERO_B256));
    xplocker = xp_locker_addr;
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
/**
    * @notice Calculates the reward amount distributed between two timestamps.
    * @param from The start of the period to measure rewards for.
    * @param to The end of the period to measure rewards for.
    * @return amount The reward amount distributed in the given period.
*/
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

abi Staking {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId);

    #[storage(read)]
    fn staked_lock_info(xp_lock_id: u64) -> StakedLockInfo;

    #[storage(read)]
    fn pending_rewards_of_lock(xp_lock_id: u64) -> u64;
    
}

impl Staking for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;

        set_registry_internal(registry);

    }

    /// @notice Information about each lock.
    /// @dev lock id => lock info
    #[storage(read)]
    fn staked_lock_info(xp_lock_id: u64) -> StakedLockInfo {
        let lock_info = storage.lock_info.get(xp_lock_id).unwrap();
        lock_info
    }

    /**
        * @notice Calculates the accumulated balance of PIDA for specified lock.
        * @param xp_lock_id The ID of the lock to query rewards for.
        * @return reward Total amount of withdrawable reward tokens.
    */
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
}
