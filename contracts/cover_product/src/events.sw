library;

/// Emitted when a new Policy is created.
pub struct PolicyCreated {
    policy_id: u64
}

/// Emitted when a Policy is updated.
pub struct PolicyUpdated {
    policy_id: u64
}

/// Emitted when a Policy is deactivated.
pub struct PolicyCanceled {
    policy_id: u64,
}

/// Emitted when Registry contract is updated.
pub struct RegistrySet {
    registry: ContractId,
}

/// Emitted when pause is set.
pub struct PauseSet {
    pause: bool,
}

/// Emitted when latest charged time is set.
pub struct LatestChargedTimeSet {
    timestamp: u64,
}

/// Emitted when max_rate is set.
pub struct MaxRateSet {
    max_rate_num: u64, 
    max_rate_denom: u64,
}

/// Emitted when charge_cycle is set.
pub struct ChargeCycleSet {
    charge_cycle: u64
}

/// Emitted when baseURI is set
pub struct BaseURISet {
    base_uri: str[32]
}

/// Emitted when debt is added for policyholder.
pub struct DebtSet {
    policyholder: Address, 
    debt_amount: u64,
}