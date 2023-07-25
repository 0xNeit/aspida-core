contract;

mod events;

use std::storage::*;
use std::constants::ZERO_B256;
use std::auth::*;
use std::block::*;

use data_provider_abi::*;
use registry_abi::*;
use events::*;
use risk_manager_abi::*;

pub struct Strategy {
    id: u64,
    weight: u64,
    status: bool,
    timestamp: u64,
}

storage {
    owner: Address = Address { value: ZERO_B256 },
    strategy_to_index: StorageMap<ContractId, u64> = StorageMap {},
    index_to_strategy: StorageMap<u64, ContractId> = StorageMap {},
    strategies: StorageMap<ContractId, Strategy> = StorageMap {},
    can_update_cover_limit: StorageMap<Identity, bool> = StorageMap {},
    active_cover_limit: u64 = 0,
    active_cover_limit_per_strategy: StorageMap<ContractId, u64> = StorageMap {},
    strategy_count: u64 = 0,
    weight_sum: u64 = 0,
    partial_reserves_factor: u64 = 0,
    registry: ContractId = ContractId { value: ZERO_B256 },
}

const MAX_BPS: u64 = 10000;

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
fn strategy_is_active_internal(strategy: ContractId) -> bool {
    let active_state = storage.strategies.get(strategy).unwrap();
    let status = active_state.status;
    return status;
}

#[storage(read)]
fn weight_per_strategy_internal(strategy: ContractId) -> u64 {
    let strategy_store = storage.strategies.get(strategy).unwrap();
    return strategy_store.weight;
}

fn as_contract_id(to: Identity) -> Option<ContractId> {
    match to {
        Identity::Address(_) => Option::None,
        Identity::ContractId(id) => Option::Some(id),
    }
}

#[storage(read)]
fn max_cover_internal() -> u64 {
    let prf = storage.partial_reserves_factor;

    let data_provider = abi(Registry, storage.registry.value).get("coverageDataProvider");
    let max_cover = abi(DataProvider, as_contract_id(data_provider).unwrap().value).max_cover() * MAX_BPS / prf;
    return max_cover;
}

#[storage(read)]
fn weight_sum_internal() -> u64 {
    if (storage.weight_sum == 0) {
        return 0;
    } else {
        return storage.weight_sum;
    } 
}

#[storage(read)]
fn active_cover_limit_internal() -> u64 {
    return storage.active_cover_limit;
}

#[storage(read)]
fn active_cover_limit_per_strategy_internal(risk_strategy: ContractId) -> u64 {
    return storage.active_cover_limit_per_strategy.get(risk_strategy).unwrap();
}

#[storage(read)]
fn min_capital_assertment_per_strategy_internal(strategy: ContractId) -> u64 {
    return active_cover_limit_per_strategy_internal(strategy) * storage.partial_reserves_factor / MAX_BPS;
}

#[storage(read)]
fn validate_allocation(strategy: ContractId, weight: u64) -> bool {

    let mut risk_strategy = storage.strategies.get(strategy).unwrap();
    let sc = storage.strategy_count;

    let mut weightsum = storage.weight_sum;
    // check if new allocation is valid for the strategy
    let mut smcr = min_capital_assertment_per_strategy_internal(strategy);
    let mc = max_cover_internal();
    weightsum = weightsum + weight - risk_strategy.weight;
    let mut new_allocation_amount = (mc * weight) / weightsum;

    if (new_allocation_amount < smcr) {
        return false;
    };

    // check other risk strategies
    let strategy_count = sc;
    let mut i = strategy_count;
    while (i > 0) {
        let strategy_store = storage.index_to_strategy.get(i).unwrap();
        risk_strategy = storage.strategies.get(strategy_store).unwrap();
        smcr = min_capital_assertment_per_strategy_internal(strategy_store);

        if (strategy_store == strategy || risk_strategy.weight == 0 || smcr == 0) {
            continue;
        };

        new_allocation_amount = (mc * risk_strategy.weight) / weightsum;

        if (new_allocation_amount < smcr) {
            return false;
        };
        i = i - 1;
    };
        
    return true;
}

impl RiskManager for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId) {
        let mut owner_store = storage.owner;
        let mut registry_store = storage.registry;
        owner_store = owner;
        registry_store = registry;
        storage.owner = owner_store;
        storage.registry = registry_store;
    }

    /***************************************
    RISK MANAGER MUTUATOR FUNCTIONS
    ***************************************/

    #[storage(read, write)]
    fn add_risk_strategy(strategy: ContractId) -> u64 {
        validate_owner();
        assert(strategy != ContractId::from(ZERO_B256));
        assert(storage.strategy_to_index.get(strategy).unwrap() == 0);

        let mut strategy_count = storage.strategy_count;
        let new_struct = Strategy {
            id: strategy_count + 1,
            weight: 0,
            status: false,
            timestamp: timestamp(),
        };

        storage.strategies.insert(strategy, new_struct);
        storage.strategy_to_index.insert(strategy, strategy_count);
        storage.index_to_strategy.insert(strategy_count, strategy);
        storage.strategy_count += 1;

        log(
            StrategyAdded {
                strategy: strategy
            }
        );

        return strategy_count;
    }

    #[storage(read, write)]
    fn set_weight_allocation(strategy: ContractId, weight: u64) {
        validate_owner();
        assert(weight > 0);
        assert(strategy_is_active_internal(strategy));
        

        let risk_strategy = storage.strategies.get(strategy).unwrap();
        storage.weight_sum = (storage.weight_sum + weight) - risk_strategy.weight;

        assert(validate_allocation(strategy, weight));

        let mut strategy_weight = risk_strategy.weight;
        strategy_weight = weight;

        let updated_struct = Strategy {
            id: risk_strategy.id,
            weight: strategy_weight,
            status: risk_strategy.status,
            timestamp: risk_strategy.timestamp,
        };

        storage.strategies.insert(strategy, updated_struct);

        log(
            RiskStrategyWeightAllocationSet {
                strategy: strategy,
                weight: weight,
            }
        );
    }

    #[storage(read, write)]
    fn set_strategy_status(strategy: ContractId, status: bool) {
        validate_owner();

        assert(strategy != ContractId::from(ZERO_B256));
        assert(storage.strategy_to_index.get(strategy).unwrap() > 0);

        let risk_strategy = storage.strategies.get(strategy).unwrap();
        let mut strategy_status = risk_strategy.status;
        strategy_status = status;

        let updated_struct = Strategy {
            id: risk_strategy.id,
            weight: risk_strategy.weight,
            status: strategy_status,
            timestamp: risk_strategy.timestamp,
        };

        storage.strategies.insert(strategy, updated_struct);

        log(
            StrategyStatusUpdated {
                strategy: strategy,
                status: status,
            }
        )
    }

    #[storage(read, write)]
    fn update_active_cover_limit_for_strategy(
        strategy: ContractId, 
        current_cover_limit: u64,
        new_cover_limit: u64,
    ) {
        let sender = msg_sender().unwrap();

        assert(storage.can_update_cover_limit.get(sender).unwrap());
        assert(strategy_is_active_internal(strategy));

        let old_cover_limit_of_strategy = storage.active_cover_limit_per_strategy.get(strategy).unwrap();
        storage.active_cover_limit = storage.active_cover_limit - current_cover_limit + new_cover_limit;
        let new_cover_limit_of_strategy = old_cover_limit_of_strategy - current_cover_limit + new_cover_limit;
        
        storage.active_cover_limit_per_strategy.insert(strategy, new_cover_limit_of_strategy);

        log(
            ActiveCoverLimitUpdated {
                strategy: strategy, 
                old_cover_limit: old_cover_limit_of_strategy, 
                new_cover_limit: new_cover_limit_of_strategy,
            }
        );
    }

    #[storage(read, write)]
    fn add_cover_limit_updater(updater: Identity) {
        validate_owner();
        storage.can_update_cover_limit.insert(updater, true);

        log(
            CoverLimitUpdaterAdded {
                updater: updater,
            }
        );
    }

    #[storage(read, write)]
    fn remove_cover_limit_updater(updater: Identity) {
        validate_owner();

        let _ = storage.can_update_cover_limit.remove(updater);

        log(
            CoverLimitUpdaterDeleted {
                updater: updater,
            }
        );
    }

    /***************************************
    RISK MANAGER VIEW FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn strategy_is_active(strategy: ContractId) -> bool {
        return strategy_is_active_internal(strategy);
    }

    #[storage(read)]
    fn strategy_at(index: u64) -> ContractId {
        return storage.index_to_strategy.get(index).unwrap();
    }

    #[storage(read)]
    fn num_strategies() -> u64 {
        return storage.strategy_count;
    }

    #[storage(read)]
    fn strategy_info(strategy: ContractId) -> (u64, u64, bool, u64) {
        let strategy_store = storage.strategies.get(strategy).unwrap();
        return (strategy_store.id, strategy_store.weight, strategy_store.status, strategy_store.timestamp);
    }

    #[storage(read)]
    fn weight_per_strategy(strategy: ContractId) -> u64 {
        return weight_per_strategy_internal(strategy);
    }

    #[storage(read)]
    fn max_cover() -> u64 {
        return max_cover_internal();
    }

    #[storage(read)]
    fn max_cover_per_strategy(strategy: ContractId) -> u64 {
        if (!strategy_is_active_internal(strategy)) {
            return 0;
        };

        let weight = weight_per_strategy_internal(strategy);
        let weight_sum = weight_sum_internal();
        let max_coverage = max_cover_internal();
        
        let cover = (max_coverage * weight) / weight_sum;

        return cover;
    }

    #[storage(read)]
    fn weight_sum() -> u64 {
        return weight_sum_internal();
    }

    #[storage(read)]
    fn active_cover_limit() -> u64 {
        return active_cover_limit_internal();
    }

    #[storage(read)]
    fn active_cover_limit_per_strategy(risk_strategy: ContractId) -> u64 {
        return active_cover_limit_per_strategy_internal(risk_strategy);
    }

    /***************************************
        MIN CAPITAL VIEW FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn min_capital_assertment() -> u64 {
        return active_cover_limit_internal() * storage.partial_reserves_factor / MAX_BPS;
    }

    #[storage(read)]
    fn min_capital_assertment_per_strategy(strategy: ContractId) -> u64 {
        return min_capital_assertment_per_strategy_internal(strategy);
    }

    #[storage(read)]
    fn partial_reserves_factor() -> u64 {
        return storage.partial_reserves_factor;
    }

    #[storage(read, write)]
    fn set_partial_reserves_factor(partial_reserves_factor: u64) {
        validate_owner();
        storage.partial_reserves_factor = partial_reserves_factor;

        log(
            PartialReservesFactorSet {
                partial_reserves_factor: partial_reserves_factor,
            }
        );
    }
}
