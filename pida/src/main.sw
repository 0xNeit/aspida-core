contract;

use std::address::*;
use std::auth::{AuthError, msg_sender};
use std::constants::ZERO_B256;
use std::token::*;
use std::storage::*;
use std::call_frames::contract_id;

use token_abi::*;

const MAX_SUPPLY: u64 = 1000000000000000000; // 1 Billion
storage {
    config: TokenInitializeConfig = TokenInitializeConfig {
        name: "            ",
        symbol: "    ",
        decimals: 9u8,
    },
    balances: StorageMap<Identity, u64> = StorageMap {},
    owner: Address = Address {
        value: ZERO_B256,
    },
    minters: StorageMap<Address, bool> = StorageMap {},
    total_supply: u64 = 0u64,
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
fn is_minter(account: Address) -> bool {
    let answer = storage.minters.get(account).unwrap();
    answer
}

#[storage(read)]
fn balance_of_internal(account: Identity) -> u64 {
    let balance = storage.balances.get(account).unwrap();
    balance
}

#[storage(read)]
fn validate_owner() {
    let sender = get_msg_sender_address_or_panic();
    assert(storage.owner == sender);
}

impl FRC20 for Contract {
    //////////////////////////////////////
    // Owner methods
    //////////////////////////////////////
    #[storage(read, write)]
    fn initialize(config: TokenInitializeConfig, owner: Address) {
        assert(storage.owner.value == ZERO_B256);
        storage.owner = owner;
        storage.config = config;
    }

    //////////////////////////////////////
    // Mint public methods
    //////////////////////////////////////
    #[storage(read, write)]
    fn mint(amount: u64) {
        assert(amount <= MAX_SUPPLY);
        let sender = get_msg_sender_address_or_panic();
        // can only be called by authorized minters
        let minter = is_minter(sender);
        assert(minter == true);
        // mint
        mint_to_address(amount, sender);
        storage.total_supply = (storage.total_supply + amount);
    }

    #[storage(read, write)]
    fn mint_to(account: Address, amount: u64) {
        assert(amount <= MAX_SUPPLY);
        let sender = get_msg_sender_address_or_panic();
        // can only be called by authorized minters
        let minter = is_minter(sender);
        assert(minter == true);
        // mint
        mint_to_address(amount, account);
        storage.total_supply = (storage.total_supply + amount);
    }

    #[storage(read)]
    fn burn(amount: u64) {
        let sender = msg_sender().unwrap();
        assert(balance_of_internal(sender) >= amount);
        burn(amount);
    }

    #[storage(read)]
    fn balance_of(account: Identity) -> u64 {
        balance_of_internal(account)
    }

    #[storage(read, write)]
    fn add_minter(minter: Address) {
        validate_owner();
        storage.minters.insert(minter, true);
    }

    #[storage(read, write)]
    fn remove_minter(minter: Address) -> bool {
        validate_owner();
        storage.minters.remove(minter)
    }

    fn transfer(coins: u64, address: Address) {
        transfer_to_address(coins, contract_id(), address);
    }

    #[storage(read)]
    fn total_supply() -> u64 {
        storage.total_supply
    }

    #[storage(read)]
    fn decimals() -> u8 {
        storage.config.decimals
    }

    #[storage(read)]
    fn name() -> str[12] {
        storage.config.name
    }

    #[storage(read)]
    fn symbol() -> str[4] {
        storage.config.symbol
    }
}
