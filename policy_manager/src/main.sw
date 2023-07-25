contract;

mod events;
mod structs;

use std::storage::*;
use std::constants::ZERO_B256;
use std::auth::*;
use std::block::*;

use events::*;
use structs::*;

use nft::{
    approved,
    is_approved_for_all,
    mint,
    owner_of,
    tokens_minted,
};

use nft::extensions::burnable::*;

use nft::extensions::token_metadata::*;

use cover_product_abi::*;
use registry_abi::*;
use risk_manager_abi::*;

struct PolicyInfo {
    cover_limit: u64,
    product: ContractId,
    expiration_block: u64,
    price: u64,
    position_description: str[20],
    risk_strategy: ContractId,
}

storage {
    owner: Address = Address { value: ZERO_B256 },
    registry: ContractId = ContractId { value: ZERO_B256 },
    policy_descriptor: ContractId = ContractId { value: ZERO_B256 },
    products: StorageMap<ContractId, u64> = StorageMap {},
    products_vec: StorageVec<ContractId> = StorageVec {},
    total_policy_count: u64 = 0,
    policy_info: StorageMap<u64, PolicyInfo> = StorageMap {},
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

fn as_contract_id(to: Identity) -> Option<ContractId> {
    match to {
        Identity::Address(_) => Option::None,
        Identity::ContractId(id) => Option::Some(id),
    }
}

#[storage(read)]
fn exists(token_id: u64) -> bool {
    let owner = owner_of(token_id);
    let mut state = false;
    if (owner.is_none()) {
        state = false;
    } else {
        state = true;
    }
    state
}

#[storage(read)]
fn token_exists(token_id: u64) {
    assert(exists(token_id) == true);
}

#[storage(read)]
fn policy_has_expired_internal(policy_id: u64) -> bool {
    token_exists(policy_id);
    let exp_block = storage.policy_info.get(policy_id).unwrap().expiration_block;
    return exp_block > 0 && exp_block < height();
}

#[storage(read, write)]
fn burn_internal(policy_id: u64) {
    // update active cover limit

    let risk_strategy = storage.policy_info.get(policy_id).unwrap().risk_strategy;
    let old_cover_limit = storage.policy_info.get(policy_id).unwrap().cover_limit;

    let deleted_meta: Option<PolicyMeta> = Option::None;
    burn(policy_id);
    set_token_metadata(deleted_meta, policy_id);

    let _ = storage.policy_info.remove(policy_id);

    let rm = abi(Registry, storage.registry.value).get("riskManager         ");
    abi(RiskManager, as_contract_id(rm).unwrap().value).update_active_cover_limit_for_strategy(risk_strategy, old_cover_limit, 0);

    log(
        PolicyBurned {
            policy_id: policy_id,
        }
    );
}

abi PolicyManager {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId);

    #[storage(read)]
    fn policy_info(policy_id: u64) -> PolicyInfo;

    #[storage(read)]
    fn get_policy_info(policy_id: u64) -> (Identity, ContractId, u64, u64, u64, str[20],ContractId);

    #[storage(read)]
    fn get_policy_holder(policy_id: u64) -> Identity;

    #[storage(read)]
    fn get_policy_product(policy_id: u64) -> ContractId;

    #[storage(read)]
    fn get_policy_expiration_block(policy_id: u64) -> u64;

    #[storage(read)]
    fn get_policy_cover_limit(policy_id: u64) -> u64;

    #[storage(read)]
    fn get_policy_price(policy_id: u64) -> u64;

    #[storage(read)]
    fn get_position_description(policy_id: u64) -> str[20];

    #[storage(read)]
    fn get_policy_risk_strategy(policy_id: u64) -> ContractId;

    #[storage(read)]
    fn policy_is_active(policy_id: u64) -> bool;

    #[storage(read)]
    fn policy_has_expired(policy_id: u64) -> bool;

    #[storage(read)]
    fn total_policy_count() -> u64;

    #[storage(read)]
    fn policy_descriptor() -> ContractId;

    #[storage(read)]
    fn registry() -> ContractId;

    #[storage(read, write)]
    fn create_policy(
        policyholder: Identity,
        cover_limit: u64,
        expiration_block: u64,
        price: u64,
        position_description: str[20],
        risk_strategy: ContractId,
    ) -> u64;

    #[storage(read, write)]
    fn set_policy_info(
        policy_id: u64,
        cover_limit: u64,
        expiration_block: u64,
        price: u64,
        position_description: str[20],
        risk_strategy: ContractId,
    );

    #[storage(read, write)]
    fn update_policy_info(
        policy_id: u64,
        cover_limit: u64,
        expiration_block: u64,
        price: u64,
    );

    #[storage(read, write)]
    fn burn(policy_id: u64);

    #[storage(read, write)]
    fn update_active_policies(policy_ids: Vec<u64>);

    #[storage(read)]
    fn product_is_active(product: ContractId) -> bool;

    #[storage(read)]
    fn num_products() -> u64;

    #[storage(read)]
    fn get_product(product_num: u64) -> ContractId;

    #[storage(read, write)]
    fn add_product(product: ContractId);

    #[storage(read, write)]
    fn remove_product(product: ContractId);

    #[storage(read, write)]
    fn set_policy_descriptor(policy_descriptor: ContractId);

    #[storage(read, write)]
    fn set_registry(registry: ContractId);
}

impl PolicyManager for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId) {
        assert(registry != ContractId::from(ZERO_B256));

        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;

        let mut registry_store = storage.registry;
        registry_store = registry;
        storage.registry = registry_store;
    }

    /***************************************
    POLICY VIEW fnS
    ***************************************/

    #[storage(read)]
    fn policy_info(policy_id: u64) -> PolicyInfo {
        token_exists(policy_id);
        let info = storage.policy_info.get(policy_id).unwrap();
        return info;
    }

    #[storage(read)]
    fn get_policy_info(policy_id: u64) -> (Identity, ContractId, u64, u64, u64, str[20],ContractId) {
        token_exists(policy_id);
        let info = storage.policy_info.get(policy_id).unwrap();
        return (
            owner_of(policy_id).unwrap(), 
            info.product, 
            info.cover_limit, 
            info.expiration_block, 
            info.price, 
            info.position_description, 
            info.risk_strategy
        );
    }

    #[storage(read)]
    fn get_policy_holder(policy_id: u64) -> Identity {
        token_exists(policy_id);
        return owner_of(policy_id).unwrap();
    }

    #[storage(read)]
    fn get_policy_product(policy_id: u64) -> ContractId {
        token_exists(policy_id);
        return storage.policy_info.get(policy_id).unwrap().product;
    }

    #[storage(read)]
    fn get_policy_expiration_block(policy_id: u64) -> u64 {
        token_exists(policy_id);
        return storage.policy_info.get(policy_id).unwrap().expiration_block;
    }

    #[storage(read)]
    fn get_policy_cover_limit(policy_id: u64) -> u64 {
        token_exists(policy_id);
        return storage.policy_info.get(policy_id).unwrap().cover_limit;
    }

    #[storage(read)]
    fn get_policy_price(policy_id: u64) -> u64 {
        token_exists(policy_id);
        return storage.policy_info.get(policy_id).unwrap().price;
    }

    #[storage(read)]
    fn get_position_description(policy_id: u64) -> str[20] {
        token_exists(policy_id);
        let position_description = storage.policy_info.get(policy_id).unwrap().position_description;
        return position_description;
    }

    #[storage(read)]
    fn get_policy_risk_strategy(policy_id: u64) -> ContractId {
        token_exists(policy_id);
        return storage.policy_info.get(policy_id).unwrap().risk_strategy;
    }

    #[storage(read)]
    fn policy_is_active(policy_id: u64) -> bool {
        token_exists(policy_id);
        return storage.policy_info.get(policy_id).unwrap().expiration_block >= height();
    }

    #[storage(read)]
    fn policy_has_expired(policy_id: u64) -> bool {
        return policy_has_expired_internal(policy_id);
    }

    #[storage(read)]
    fn total_policy_count() -> u64 {
        return storage.total_policy_count;
    }

    #[storage(read)]
    fn policy_descriptor() -> ContractId {
        return storage.policy_descriptor;
    }

    #[storage(read)]
    fn registry() -> ContractId {
        return storage.registry;
    }

    /***************************************
    POLICY MUTATIVE fnS
    ***************************************/

    #[storage(read, write)]
    fn create_policy(
        policyholder: Identity,
        cover_limit: u64,
        expiration_block: u64,
        price: u64,
        position_description: str[20],
        risk_strategy: ContractId,
    ) -> u64 {
        let sender = as_contract_id(msg_sender().unwrap()).unwrap();

        assert(storage.products.get(sender).is_some());

        let info = PolicyInfo {
            product: sender,
            position_description: position_description,
            expiration_block: expiration_block,
            cover_limit: cover_limit,
            price: price,
            risk_strategy: risk_strategy
        };

        let policy_id = storage.total_policy_count + 1; // starts at 1

        storage.policy_info.insert(policy_id, info);

        mint(1, policyholder);
        set_token_metadata(Option::Some(PolicyMeta::new()), policy_id);
       
        // update active cover limit
        let rm = abi(Registry, storage.registry.value).get("riskManager         ");
        abi(RiskManager, as_contract_id(rm).unwrap().value).update_active_cover_limit_for_strategy(risk_strategy, 0, cover_limit);

        log(
            PolicyCreated {
                policy_id : policy_id,
            }
        );
        return policy_id;
    }

    #[storage(read, write)]
    fn set_policy_info(
        policy_id: u64,
        cover_limit: u64,
        expiration_block: u64,
        price: u64,
        position_description: str[20],
        risk_strategy: ContractId,
    ) {
        token_exists(policy_id);

        let sender = as_contract_id(msg_sender().unwrap()).unwrap();

        assert(storage.policy_info.get(policy_id).unwrap().product == sender);
       
        let old_cover_limit = storage.policy_info.get(policy_id).unwrap().cover_limit;
        
        let info = PolicyInfo {
            product: sender,
            position_description: position_description,
            expiration_block: expiration_block,
            cover_limit: cover_limit,
            price: price,
            risk_strategy: risk_strategy
        };

        storage.policy_info.insert(policy_id, info);
        let rm = abi(Registry, storage.registry.value).get("riskManager         ");
        // update active cover limit
        abi(RiskManager, as_contract_id(rm).unwrap().value).update_active_cover_limit_for_strategy(risk_strategy, old_cover_limit, cover_limit);

        log(
            PolicyUpdated {
                policy_id: policy_id,
            }
        );
    }

    #[storage(read, write)]
    fn update_policy_info(
        policy_id: u64,
        cover_limit: u64,
        expiration_block: u64,
        price: u64,
    ) {
        token_exists(policy_id);

        let sender = as_contract_id(msg_sender().unwrap()).unwrap();

        assert(storage.policy_info.get(policy_id).unwrap().product == sender);
        // strategy
        let strategy = storage.policy_info.get(policy_id).unwrap().risk_strategy;

        let old_cover_limit = storage.policy_info.get(policy_id).unwrap().cover_limit;
        
        let info = PolicyInfo {
            product: sender,
            position_description: storage.policy_info.get(policy_id).unwrap().position_description,
            expiration_block: expiration_block,
            cover_limit: cover_limit,
            price: price,
            risk_strategy: strategy
        };

        storage.policy_info.insert(policy_id, info);

        let rm = abi(Registry, storage.registry.value).get("riskManager         ");
        // update active cover limit
        abi(RiskManager, as_contract_id(rm).unwrap().value).update_active_cover_limit_for_strategy(strategy, old_cover_limit, cover_limit);
        
        log(
            PolicyUpdated {
                policy_id: policy_id,
            }
        );
    }

    #[storage(read, write)]
    fn burn(policy_id: u64) {
        token_exists(policy_id);

        let sender = as_contract_id(msg_sender().unwrap()).unwrap();

        assert(storage.policy_info.get(policy_id).unwrap().product == sender);

        burn_internal(policy_id);
    }

    #[storage(read, write)]
    fn update_active_policies(policy_ids: Vec<u64>) {
        let mut i = 0;

        while (i < policy_ids.len()) {
            let policy_id = policy_ids.get(i).unwrap();
            // dont burn active or nonexistent policies
            if (policy_has_expired_internal(policy_id)) {
                let product = storage.policy_info.get(policy_id).unwrap().product;
                let cover_limit = storage.policy_info.get(policy_id).unwrap().cover_limit;
                // update active cover limit
                let rm = abi(Registry, storage.registry.value).get("riskManager         ");
                abi(RiskManager, as_contract_id(rm).unwrap().value).update_active_cover_limit_for_strategy(
                    storage.policy_info.get(policy_id).unwrap().risk_strategy, 
                    storage.policy_info.get(policy_id).unwrap().cover_limit, 
                    0
                );
                abi(CoverProduct, product.value).update_active_cover_limit(
                    cover_limit, 
                    0,
                );

                burn_internal(policy_id);
            };

            i += 1;
        };
    }

    /***************************************
    PRODUCT VIEW fnS
    ***************************************/

    #[storage(read)]
    fn product_is_active(product: ContractId) -> bool {
        return storage.products.get(product).is_some();
    }

    #[storage(read)]
    fn num_products() -> u64 {
        return storage.products_vec.len();
    }

    #[storage(read)]
    fn get_product(product_num: u64) -> ContractId {
        return storage.products_vec.get(product_num).unwrap();
    }

    /***************************************
    GOVERNANCE fnS
    ***************************************/

    #[storage(read, write)]
    fn add_product(product: ContractId) {
        validate_owner();
        assert(product != ContractId::from(ZERO_B256));

        storage.products_vec.push(product);

        let index = storage.products_vec.len();
        storage.products.insert(product, index);

        log(
            ProductAdded {
                product: product,
            }
        );
    }

    #[storage(read, write)]
    fn remove_product(product: ContractId) {
        validate_owner();
        let index = storage.products.get(product).unwrap();

        let _ = storage.products.remove(product);
        let _ = storage.products_vec.remove(index);

        log(
            ProductRemoved {
                product: product,
            }
        );
    }

    #[storage(read, write)]
    fn set_policy_descriptor(policy_descriptor: ContractId) {
        validate_owner();
        storage.policy_descriptor = policy_descriptor;

        log(
            PolicyDescriptorSet {
                policy_descriptor: policy_descriptor,
            }
        )
    }

    #[storage(read, write)]
    fn set_registry(registry: ContractId) {
        validate_owner();
        assert(registry != ContractId::from(ZERO_B256));
        storage.registry = registry;

        log(
            RegistrySet {
                registry: registry,
            }
        );
    }
}
