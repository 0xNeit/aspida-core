library;

use locker_abi::Lock;

abi Staking {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId);

    #[storage(read)]
    fn staked_lock_info(xp_lock_id: u64) -> StakedLockInfo;

    #[storage(read)]
    fn pending_rewards_of_lock(xp_lock_id: u64) -> u64;

    #[storage(read, write)]
    fn register_lock_event(
        xp_lock_id: u64,
        old_owner: Address,
        new_owner: Address,
        old_lock: Lock,
        new_lock: Lock,
    );

    #[storage(read, write)]
    fn harvest_lock(xp_lock_id: u64);
    
    #[storage(read, write)]
    fn harvest_locks(xp_lock_ids: Vec<u64>);
}

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
