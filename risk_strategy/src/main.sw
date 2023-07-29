contract;

mod events;

use std::constants::ZERO_B256;
use std::auth::*;
use std::storage::*;
use std::call_frames::*;

use events::*;
use risk_manager_abi::*;

/// Struct for a product's risk parameters.
pub struct ProductRiskParams {
    weight: u64,  // The weighted allocation of this product vs other products.
    price: u64,   
    divisor: u64, // The max cover per policy divisor. (maxCoverPerProduct / divisor = maxCoverPerPolicy)
}

storage {
    owner: Address = Address { value: ZERO_B256 },
    product_to_index: StorageMap<ContractId, u64> = StorageMap {},
    index_to_product: StorageMap<u64, ContractId> = StorageMap {},
    product_risk_params: StorageMap<ContractId, ProductRiskParams> = StorageMap {},
    product_count: u64 = 0,
    risk_manager: ContractId = ContractId { value: ZERO_B256 },
    strategist: Address = Address { value: ZERO_B256 },
    weight_sum: u64 = 0,
}

fn as_contract_id(to: Identity) -> Option<ContractId> {
    match to {
        Identity::Address(_) => Option::None,
        Identity::ContractId(id) => Option::Some(id),
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
fn only_risk_manager() {
    let sender = as_contract_id(msg_sender().unwrap()).unwrap();

    assert(sender == storage.risk_manager);
}

#[storage(read, write)]
fn initialize_strategy_risk_params(
    products: Vec<ContractId>, 
    weights: Vec<u64>,
    prices: Vec<u64>, 
    divisors: Vec<u64>,
) {
    let length = products.len();
    assert(length > 0 && (length == weights.len() && length == prices.len() && length == divisors.len()));
    let mut weightsum = 0;
    let mut i = 0;

    while (i < length) {
        assert(products.get(i).unwrap() != ContractId::from(ZERO_B256));
        assert(weights.get(i).unwrap() > 0);
        assert(prices.get(i).unwrap() > 0);
        assert(divisors.get(i).unwrap() > 0);

        let new_struct = ProductRiskParams {
            weight : weights.get(i).unwrap(),
            price : prices.get(i).unwrap(),
            divisor : divisors.get(i).unwrap(),
        };

        storage.product_risk_params.insert(products.get(i).unwrap(), new_struct);
        storage.product_to_index.insert(products.get(i).unwrap(), i + 1);
        storage.index_to_product.insert(i + 1, products.get(i).unwrap());

        weightsum += weights.get(i).unwrap();

        log(
            ProductRiskParamsSet {
                product: products.get(i).unwrap(), 
                weight: weights.get(i).unwrap(), 
                price: prices.get(i).unwrap(), 
                divisor: divisors.get(i).unwrap(),
            }
        );

        i = i + 1;
    }
    
    storage.weight_sum = weightsum;
    storage.product_count = length;
}

#[storage(read)]
fn max_cover_internal() -> u64 {
    let cover = abi(RiskManager, storage.risk_manager.value).max_cover_per_strategy(contract_id());
    return cover;
}

#[storage(read)]
fn  max_cover_per_product_internal(prod: ContractId) -> u64 {
    return max_cover_internal() * storage.product_risk_params.get(prod).unwrap().weight / storage.weight_sum;
}

#[storage(read)]
fn status_internal() -> bool {
    let rm = abi(RiskManager, storage.risk_manager.value).strategy_is_active(contract_id());
    return rm;
}

abi RiskStrategy {
    #[storage(read, write)]
    fn initialize(
        owner: Address,
        risk_manager: ContractId,
        strategist: Address,
        products: Vec<ContractId>,
        weights: Vec<u64>,
        prices: Vec<u64>,
        divisors: Vec<u64>,
    );

    #[storage(read)]
    fn assess_risk(prod: ContractId, current_cover: u64, new_cover: u64) -> (bool, u64);

    #[storage(read)]
    fn max_cover() -> u64;

    #[storage(read)]
    fn max_cover_per_product(prod: ContractId) -> u64;

    #[storage(read)]
    fn sellable_cover_per_product(prod: ContractId) -> u64;

    #[storage(read)]
    fn max_cover_per_policy(prod: ContractId) -> u64;

    #[storage(read)]
    fn product_is_active(prod: ContractId) -> bool;

    #[storage(read)]
    fn num_products() -> u64;

    #[storage(read)]
    fn product(index: u64) -> ContractId;

    #[storage(read)]
    fn product_risk_params(prod: ContractId) -> (u64, u64, u64);

    #[storage(read)]
    fn weight_sum() -> u64;

    #[storage(read)]
    fn weight_allocation() -> u64;

    #[storage(read)]
    fn strategist() -> Address;

    #[storage(read)]
    fn status() -> bool;

    #[storage(read)]
    fn risk_manager() -> ContractId;

    #[storage(read, write)]
    fn add_product(prod: ContractId, weight: u64, price: u64, divisor: u64);

    #[storage(read, write)]
    fn remove_product(prod: ContractId);

    #[storage(read, write)]
    fn set_product_params(
        products: Vec<ContractId>, 
        weights: Vec<u64>, 
        prices: Vec<u64>, 
        divisors: Vec<u64>,
    );

    #[storage(read, write)]
    fn set_risk_manager(risk_manager: ContractId);
}

impl RiskStrategy for Contract {
    #[storage(read, write)]
    fn initialize(
        owner: Address,
        risk_manager: ContractId,
        strategist: Address,
        products: Vec<ContractId>,
        weights: Vec<u64>,
        prices: Vec<u64>,
        divisors: Vec<u64>,
    ) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;

        assert(risk_manager != ContractId::from(ZERO_B256));

        let mut risk_store = storage.risk_manager;
        risk_store = risk_manager;
        storage.risk_manager = risk_store;

        assert(strategist != Address::from(ZERO_B256));

        let mut strategist_store = storage.strategist;
        strategist_store = strategist;
        storage.strategist = strategist_store;

        // set strategy product risk params
        initialize_strategy_risk_params(products, weights, prices, divisors);
    }

    /***************************************
      RISK STRATEGY VIEW fnS
    ***************************************/

    #[storage(read)]
    fn assess_risk(prod: ContractId, current_cover: u64, new_cover: u64) -> (bool, u64) {
        assert(status_internal());
        assert(storage.product_to_index.get(prod).unwrap() > 0);

        // max cover checks
        let mut mc = max_cover_internal();
        let params = storage.product_risk_params.get(prod).unwrap();

        // must be less than maxCoverPerProduct
        mc = mc * params.weight / storage.weight_sum;
        let mut product_active_cover_limit = abi(RiskManager, storage.risk_manager.value).active_cover_limit_per_strategy(contract_id());
        product_active_cover_limit = product_active_cover_limit + new_cover - current_cover;
    
        if (product_active_cover_limit > mc) {
            return (false, params.price);
        };

        // must be less than maxCoverPerPolicy
        mc = mc / params.divisor;

        if (new_cover > mc) {
            return (false, params.price);
        };

        // risk is acceptable
        return (true, params.price);
    }
    
    #[storage(read)]
    fn max_cover() -> u64 {
        return max_cover_internal();
    }

    #[storage(read)]
    fn max_cover_per_product(prod: ContractId) -> u64 {
        return max_cover_per_product_internal(prod);
    }

    #[storage(read)]
    fn sellable_cover_per_product(prod: ContractId) -> u64 {
        // max cover per product
        let mc = max_cover_per_product_internal(prod);
        // active cover for product
        let ac = abi(RiskManager, storage.risk_manager.value).active_cover_limit_per_strategy(contract_id());
        
        if (mc < ac) {
            return 0;
        } else {
            return mc - ac;
        }
    }

    #[storage(read)]
    fn max_cover_per_policy(prod: ContractId) -> u64 {
        let params = storage.product_risk_params.get(prod).unwrap();
        assert(params.weight > 0);
        return max_cover_internal() * params.weight / (storage.weight_sum * params.divisor);
    }

    #[storage(read)]
    fn product_is_active(prod: ContractId) -> bool {
        return storage.product_to_index.get(prod).unwrap() != 0;
    }

    #[storage(read)]
    fn num_products() -> u64 {
        return storage.product_count;
    }

    #[storage(read)]
    fn product(index: u64) -> ContractId {
      return storage.index_to_product.get(index).unwrap();
    }

    #[storage(read)]
    fn product_risk_params(prod: ContractId) -> (u64, u64, u64) {
        let params = storage.product_risk_params.get(prod).unwrap();
        assert(params.weight > 0);
        return (params.weight, params.price, params.divisor);
    }

    #[storage(read)]
    fn weight_sum() -> u64 {
        return storage.weight_sum;
    }

    #[storage(read)]
    fn weight_allocation() -> u64 {
        let rm = abi(RiskManager, storage.risk_manager.value).weight_per_strategy(contract_id()); 
        return rm;
    }

    #[storage(read)]
    fn strategist() -> Address {
        return storage.strategist;
    }

    #[storage(read)]
    fn status() -> bool {
        return status_internal();
    }

    #[storage(read)]
    fn risk_manager() -> ContractId {
        return storage.risk_manager;
    }

    /***************************************
    GOVERNANCE fnS
    ***************************************/

    #[storage(read, write)]
    fn add_product(prod: ContractId, weight: u64, price: u64, divisor: u64) {
        validate_owner();
        assert(prod != ContractId::from(ZERO_B256));
        assert(weight > 0);
        assert(price > 0);
        assert(divisor > 0);

        let mut index = storage.product_to_index.get(prod).unwrap();
        let mut weight_sum = storage.weight_sum;
        if (index == 0) {
            // add new product
            if (storage.product_count == 0) {
                weight_sum = weight;
            } else {
                weight_sum = (weight_sum + weight);
            };

            let new_struct1 = ProductRiskParams {
                weight: weight,
                price: price,
                divisor: divisor,
            };

            storage.product_risk_params.insert(prod, new_struct1);
            
            index = storage.product_count;
            storage.product_to_index.insert(prod, index + 1);
            storage.index_to_product.insert(index + 1, prod);
            
            storage.product_count += 1; 
            
            log(
                ProductAddedByGovernance {
                    product: prod, 
                    weight: weight, 
                    price: price, 
                    divisor: price,
                }
            );
        } else {
            // change params of existing product
            let prev_weight = storage.product_risk_params.get(prod).unwrap().weight;
            weight_sum = weight_sum - prev_weight + weight;

            let new_struct2 = ProductRiskParams {
                weight: weight,
                price: price,
                divisor: divisor,
            };

            storage.product_risk_params.insert(prod, new_struct2);

            log(
                ProductUpdatedByGovernance {
                    product: prod, 
                    weight: weight, 
                    price: price, 
                    divisor: price,
                }
            );
        };

        storage.weight_sum = weight_sum;
    }

    #[storage(read, write)]
    fn remove_product(prod: ContractId) {
        validate_owner();
        let index = storage.product_to_index.get(prod).unwrap();
        let product_count = storage.product_count;

        if (product_count == 0) {
            return;
        };

        // product wasn't added to begin with
        if (index == 0) {
            return;
        };

        // if not at the end copy down
        let last_index = product_count;
        if (index != last_index) {
            let last_product = storage.index_to_product.get(last_index).unwrap();
            storage.product_to_index.insert(last_product, index);
            storage.index_to_product.insert(index, last_product);
        };

        // pop end of array
        storage.product_to_index.remove(prod);
        storage.index_to_product.remove(last_index);
        
        let new_product_count = product_count - 1;

        if (new_product_count == 0) {
            storage.weight_sum = 0;
        } else {
            storage.weight_sum = (storage.weight_sum - storage.product_risk_params.get(prod).unwrap().weight);
        }

        storage.product_count = new_product_count;
        storage.product_risk_params.remove(prod);

        log(
            ProductRemovedByGovernance {
                product: prod,
            }
        );
    }

    #[storage(read, write)]
    fn set_product_params(
        products: Vec<ContractId>, 
        weights: Vec<u64>, 
        prices: Vec<u64>, 
        divisors: Vec<u64>,
    ) {
        validate_owner();
        // check array lengths
        let length = products.len();
        assert(length == weights.len() && length == prices.len() && length == divisors.len());
        
        // delete old products
        let mut index = storage.product_count;
        while (index > 0) {
            let prod = storage.index_to_product.get(index).unwrap();
            storage.product_to_index.remove(prod);
            storage.index_to_product.remove(index);
            storage.product_risk_params.remove(prod);

            log(
                ProductRiskParamsSetByGovernance {
                    product: prod, 
                    weight: 0, 
                    price: 0, 
                    divisor: 0,
                }
            );

            index -= 1;
        }
        
        // add new products
        let mut weight_sum = 0;
        let mut i = 0;
        while (i < length) {
            let prod = products.get(i).unwrap();
            let weight = weights.get(i).unwrap();
            let price = prices.get(i).unwrap();
            let divisor = divisors.get(i).unwrap();

            assert(prod != ContractId::from(ZERO_B256));
            assert(weight > 0);
            assert(price > 0);
            assert(divisor > 0);
            assert(storage.product_to_index.get(prod).unwrap() == 0);

            let new_struct = ProductRiskParams {
                weight: weight,
                price: price,
                divisor: divisor
            };

            storage.product_risk_params.insert(prod, new_struct);

            weight_sum += weight;
            storage.product_to_index.insert(prod, i + 1);
            storage.index_to_product.insert(i + 1, prod);

            log(
                ProductRiskParamsSetByGovernance {
                    product: prod,
                    weight: weight,
                    price: price,
                    divisor: divisor,
                }
            );

            i += 1;
        };
        
        if (length == 0) {
            storage.weight_sum = 0;
        } else {
            storage.weight_sum = weight_sum;
        };

        storage.product_count = length;
    }

    #[storage(read, write)]
    fn set_risk_manager(risk_manager: ContractId) {
        validate_owner();
        assert(risk_manager != ContractId::from(ZERO_B256));
        storage.risk_manager = risk_manager;

        log(
            RiskManagerSet {
                risk_manager: risk_manager,
            }
        );
    }
}
