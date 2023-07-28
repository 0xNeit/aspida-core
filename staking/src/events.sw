library;

use locker_abi::Lock;

/// Emitted when the global information is updated.
pub struct Updated {}
    
/// Emitted when a locks information is updated.
pub struct LockUpdated {
    xp_lock_id: u64
}

/// Emitted when the reward rate is set.
pub struct RewardsSet {
    reward_per_second: u64
}

/// Emitted when the farm times are set.
pub struct FarmTimesSet {
    start_time: u64, 
    end_time: u64
}

pub struct LockEvent {
    xp_lock_id: u64,
    old_owner: Address,
    new_owner: Address,
    old_lock: Lock,
    new_lock: Lock,
}
    
/// Emitted when the registry is set.
pub struct RegistrySet {
    registry: ContractId
}