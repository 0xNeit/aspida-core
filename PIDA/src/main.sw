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
    balances: StorageMap<Address, u64> = StorageMap {},
    owner: Address = Address {
        value: ZERO_B256,
    },
    minters: StorageMap<Address, bool> = StorageMap {},
    total_supply: u64 = 0u64,
}

enum Error {
    CannotReinitialize: (),
    MintIsClosed: (),
    NotOwner: (),
    NotMinter: (),
    InsufficientAmount: (),
}

pub fn get_msg_sender_address_or_panic() -> Address {
    let sender: Result<Identity, AuthError> = msg_sender();
    if let Identity::Address(address) = sender.unwrap() {
        address
    } else {
        revert(0);
    }
}

/**
    * @notice Returns true if `account` is authorized to mint PIDA.
    * @param account Account to query.
    * @return status True if `account` can mint, false otherwise.
*/
#[storage(read)]
fn is_minter(account: Address) -> bool {
    let answer = storage.minters.get(account).read();
    answer
}

/**
    * @dev Returns the amount of tokens owned by `account`.
*/
#[storage(read)]
fn balance_of(account: Address) -> u64 {
    let balance = storage.balances.get(account).read();
    balance
}

#[storage(read)]
fn validate_owner() {
    let sender = get_msg_sender_address_or_panic();
    require(storage.owner.read() == sender, Error::NotOwner);
}

impl PIDA for Contract {
    //////////////////////////////////////
    // Owner methods
    //////////////////////////////////////
    #[storage(read, write)]
    fn initialize(config: TokenInitializeConfig, owner: Address) {
        require(storage.owner.value.read() == ZERO_B256, Error::CannotReinitialize);
        storage.owner.write(owner);
        storage.config.write(config);
    }

    //////////////////////////////////////
    // Mint public methods
    //////////////////////////////////////
    #[storage(read, write)]
    fn mint(amount: u64) {
        require(amount <= MAX_SUPPLY, Error::MintIsClosed);
        let sender = get_msg_sender_address_or_panic();
        // can only be called by authorized minters
        let minter = is_minter(sender);
        require(minter == true, Error::NotMinter);
        // mint
        mint_to_address(amount, sender);
        storage.total_supply.write(storage.total_supply.read() + amount);
    }
    /**
     * @notice Mints new PIDA to the receiver account.
     * Can only be called by authorized minters.
     * @param account The receiver of new tokens.
     * @param amount The number of new tokens.
     */
    #[storage(read, write)]
    fn mint_to(account: Address, amount: u64) {
        require(amount <= MAX_SUPPLY, Error::MintIsClosed);
        let sender = get_msg_sender_address_or_panic();
        // can only be called by authorized minters
        let minter = is_minter(sender);
        require(minter == true, Error::NotMinter);
        // mint
        mint_to_address(amount, account);
        storage.total_supply.write(storage.total_supply.read() + amount);
    }

    /**
     * @notice Burns PIDA from msg_sender.
     * @param amount Amount to burn.
     */
    #[storage(read)]
    fn burn(amount: u64) {
        let sender = get_msg_sender_address_or_panic();
        require(balance_of(sender) >= amount, Error::InsufficientAmount);
        burn(amount);
    }

    /**
     * @notice Adds a new minter.
     * Can only be called by the current Owner.
     * @param minter The new minter.
     */
    #[storage(read, write)]
    fn add_minter(minter: Address) {
        validate_owner();
        storage.minters.insert(minter, true);
    }

    /**
     * @notice Removes a minter.
     * Can only be called by the current Owner.
     * @param minter The minter to remove.
     */
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
        storage.total_supply.read()
    }

    #[storage(read)]
    fn decimals() -> u8 {
        storage.config.decimals.read()
    }

    #[storage(read)]
    fn name() -> str[12] {
        storage.config.name.read()
    }

    #[storage(read)]
    fn symbol() -> str[4] {
        storage.config.symbol.read()
    }
}
