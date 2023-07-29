library;

abi RiskManager {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId);

    #[storage(read, write)]
    fn add_risk_strategy(strategy: ContractId) -> u64;

    #[storage(read, write)]
    fn set_weight_allocation(strategy: ContractId, weight: u64);
    
    #[storage(read, write)]
    fn set_strategy_status(strategy: ContractId, status: bool);

    #[storage(read, write)]
    fn update_active_cover_limit_for_strategy(
        strategy: ContractId, 
        current_cover_limit: u64,
        new_cover_limit: u64,
    );

    #[storage(read, write)]
    fn add_cover_limit_updater(updater: Identity);

    #[storage(read, write)]
    fn remove_cover_limit_updater(updater: Identity);

    #[storage(read)]
    fn strategy_is_active(strategy: ContractId) -> bool;

    #[storage(read)]
    fn strategy_at(index: u64) -> ContractId;

    #[storage(read)]
    fn num_strategies() -> u64;

    #[storage(read)]
    fn strategy_info(strategy: ContractId) -> (u64, u64, bool, u64);

    #[storage(read)]
    fn weight_per_strategy(strategy: ContractId) -> u64;

    #[storage(read)]
    fn max_cover() -> u64;

    #[storage(read)]
    fn max_cover_per_strategy(strategy: ContractId) -> u64;

    #[storage(read)]
    fn weight_sum() -> u64;

    #[storage(read)]
    fn active_cover_limit() -> u64;

    #[storage(read)]
    fn active_cover_limit_per_strategy(risk_strategy: ContractId) -> u64;

    #[storage(read)]
    fn min_capital_assertment() -> u64;

    #[storage(read)]
    fn min_capital_assertment_per_strategy(strategy: ContractId) -> u64;

    #[storage(read)]
    fn partial_reserves_factor() -> u64;

    #[storage(read, write)]
    fn set_partial_reserves_factor(partial_reserves_factor: u64);
}