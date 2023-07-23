contract;

use std::constants::ZERO_B256;
use std::token::*;
use std::call_frames::*;
use std::context::*;
use std::assert::*;
use std::auth::*;

use premium_pool_abi::*;

storage {
    owner: Address = Address { value: ZERO_B256 },
}

fn balance_internal(token: ContractId) -> u64 {
    return this_balance(token);
}

impl PremiumPool for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;
    }

    fn deposit_token(amount: u64, token: ContractId) {
        force_transfer_to_contract(amount, token, contract_id());
    }

    fn balance(token: ContractId) -> u64 {
        return balance_internal(token);
    }

    fn withdraw(amount: u64, token: ContractId, to: Identity) {
        assert(balance_internal(token) >= amount);
        assert(amount > 0);

        transfer(amount, token, to);
    }
}
