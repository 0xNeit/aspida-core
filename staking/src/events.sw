library;

use locker_abi::Lock;

/// /// @notice Emitted when the global information is updated.
pub struct Updated {}
    
/// @notice Emitted when a locks information is updated.
pub struct LockUpdated {
    xp_lock_id: u64
}

/// @notice Emitted when the reward rate is set.
pub struct RewardsSet {
    reward_per_second: u64
}

/// @notice Emitted when the farm times are set.
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
    
/// /// @notice Emitted when the registry is set.
pub struct RegistrySet {
    registry: ContractId
}