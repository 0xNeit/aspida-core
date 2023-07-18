contract;

use std::constants::ZERO_B256;
use std::assert::*;

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
/*fn _setRegistry(registry: ContractId) {
    assert(registry != ContractId::from(ZERO_B256));
    let mut reg = storage.registry;
    reg = registry;
    storage.registry = reg;

        IRegistry reg = IRegistry(_registry);

        // set scp
        (, address coverPaymentManagerAddr) = reg.tryGet("coverPaymentManager");
        require(coverPaymentManagerAddr != address(0x0), "zero address payment manager");
        coverPaymentManager = coverPaymentManagerAddr;

        // set solace
        (, address solaceAddr) = reg.tryGet("solace");
        require(solaceAddr != address(0x0), "zero address solace");
        solace = solaceAddr;

        // set xslocker
        (, address xslockerAddr) = reg.tryGet("xsLocker");
        require(xslockerAddr != address(0x0), "zero address xslocker");
        xsLocker = xslockerAddr;

        // approve solace
        IERC20(solaceAddr).approve(xslockerAddr, type(uint256).max);
        IERC20(solaceAddr).approve(coverPaymentManagerAddr, type(uint256).max);

        emit RegistrySet(_registry);
    }*/

abi Staking {
    fn initialize(owner: Address, registry: ContractId);
    
}

impl Staking for Contract {
    fn initialize(owner: Address, registry: ContractId) {

    }
}
