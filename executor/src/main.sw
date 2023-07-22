contract;

mod events;
mod structs;

use std::constants::ZERO_B256;
use std::storage::*;
use std::auth::*;
use std::block::*;
use std::hash::*;
use std::b512::B512;
use std::ecr::*;

use events::*;
use structs::*;

storage {
    executors: StorageVec<Address> = StorageVec {},
    owner: Address = Address { value: ZERO_B256 },
}

abi Executor {
    #[storage(read, write)]
    fn inititalize(owner: Address);

    #[storage(read)]
    fn num_executors() -> u64;

    #[storage(read)]
    fn get_executor(index: u64) -> Address;

    #[storage(read)]
    fn is_executor(executor: Address) -> bool;

    #[storage(read)]
    fn verify_price(
        token: ContractId,
        price: u64,
        deadline: u64,
        signature: B512,
    ) -> bool;

    #[storage(read)]
    fn verify_premium(
        premium: u64,
        policy_holder: Address,
        deadline: u64,
        signature: B512,
    ) -> bool;

    #[storage(read, write)]
    fn add_executor(executor: Address);

    #[storage(read, write)]
    fn remove_executor(index: u64) -> Address;
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
fn is_executor_internal(executor: Address) -> bool {
    let mut index = 0;
    let len = storage.executors.len();
    let mut answer = false;
     while (index < len) {
        if (storage.executors.get(index).unwrap() == executor) {
            answer = true;
        } else {
            answer = false;
        }
        index = index + 1;
    }
    return answer;
}

impl Executor for Contract {
    #[storage(read, write)]
    fn inititalize(owner: Address) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn num_executors() -> u64 {
        let len = storage.executors.len();
        return len;
    }

    #[storage(read)]
    fn get_executor(index: u64) -> Address {
        let at = storage.executors.get(index).unwrap();
        return at;
    }

    #[storage(read)]
    fn is_executor(executor: Address) -> bool {
        return is_executor_internal(executor);
    }

    /***************************************
    VERIFY FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn verify_price(
        token: ContractId,
        price: u64,
        deadline: u64,
        signature: B512,
    ) -> bool {
        assert(token != ContractId::from(ZERO_B256));
        assert(price > 0);
        assert(timestamp() <= deadline);

        let price_struct = PriceData {
            token: token,
            price: price,
            deadline: deadline,
        };

        let hashed_struct = keccak256(price_struct);
        let executor = ec_recover_address(signature, hashed_struct);

        if (executor.is_ok()) {
            return is_executor_internal(executor.unwrap());
        } else {
            return false;
        }
    }

    #[storage(read)]
    fn verify_premium(
        premium: u64,
        policy_holder: Address,
        deadline: u64,
        signature: B512,
    ) -> bool {
        assert(timestamp() <= deadline);
        assert(policy_holder != Address::from(ZERO_B256));

        let premium_struct = PremiumData {
            premium: premium,
            policy_holder: policy_holder,
            deadline: deadline,
        };

        let hashed_struct = keccak256(premium_struct);
        let executor = ec_recover_address(signature, hashed_struct);

        if (executor.is_ok()) {
            return is_executor_internal(executor.unwrap());
        } else {
            return false;
        }
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    #[storage(read, write)]
    fn add_executor(executor: Address) {
        validate_owner();
        assert(executor != Address::from(ZERO_B256));
        storage.executors.push(executor);

        log(
            ExecutorAdded {
                executor: executor,
            }
        );
    }

    #[storage(read, write)]
    fn remove_executor(index: u64) -> Address {
        validate_owner();
        let removed_addr = storage.executors.remove(index);
        return removed_addr;
    }
}
