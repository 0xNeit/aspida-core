library;

/// Emitted when new strategy is created.
pub struct StrategyAdded {
    strategy: ContractId,
}

/// Emitted when strategy status is updated.
pub struct StrategyStatusUpdated {
    strategy: ContractId,
    status: bool,
}

/// Emitted when strategy's allocation weight is increased.
pub struct RiskStrategyWeightAllocationIncreased {
    strategy: ContractId,
    weight: u64,
}

/// Emitted when strategy's allocation weight is decreased.
pub struct RiskStrategyWeightAllocationDecreased {
    strategy: ContractId,
    weight: u64,
}

/// Emitted when strategy's allocation weight is set.
pub struct RiskStrategyWeightAllocationSet {
    strategy: ContractId,
    weight: u64,
}

/// Emitted when the partial reserves factor is set.
pub struct PartialReservesFactorSet {
    partial_reserves_factor: u64,
}

/// Emitted when the cover limit amount of the strategy is updated.
pub struct ActiveCoverLimitUpdated {
    strategy: ContractId,
    old_cover_limit: u64,
    new_cover_limit: u64,
}

/// Emitted when the cover limit updater is set.
pub struct CoverLimitUpdaterAdded {
    updater: Identity,
}

/// Emitted when the cover limit updater is removed.
pub struct CoverLimitUpdaterDeleted {
    updater: Identity,
}
