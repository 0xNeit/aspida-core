contract;

use std::contract_id::ContractId;
use std::constants::ZERO_B256;
use std::address::Address;
use std::storage::*;
use std::auth::{AuthError, msg_sender};

use token_abi::*;

abi BondsRegistry {
    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId);

    #[storage(read, write)]
    fn add_teller(teller: Address);

    #[storage(read, write)]
    fn remove_teller(teller: Address) -> bool;

    #[storage(read)]
    fn pull_pida(amount: u64);
}

storage {
    pida: ContractId = ContractId {
        value: ZERO_B256,
    },
    is_teller: StorageMap<Address, bool> = StorageMap {},
    owner: Address = Address {
        value: ZERO_B256,
    },
}

enum Error {
    CannotReinitialize: (),
    NotOwner: (),
    NotTeller: (),
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
    require(storage.owner == sender, Error::NotOwner);
}

impl BondsRegistry for Contract {
    /**
     * @notice Initializes the BondsRegistry contract.
     * @param owner The address of the owner.
     * @param pida ContractId of PIDA.
     */
    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId) {
        require(storage.pida.value == ZERO_B256, Error::CannotReinitialize);
        require(storage.owner.value == ZERO_B256, Error::CannotReinitialize);
        storage.pida = pida;
        storage.owner = owner;
    }

    /***************************************
    TELLER MANAGEMENT FUNCTIONS
    ***************************************/

    /**
     * @notice Adds a teller.
     * Can only be called by the current owner.
     * @param teller The teller to add.
     */
    #[storage(read, write)]
    fn add_teller(teller: Address) {
        validate_owner();
        storage.is_teller.insert(teller, true);
    }

    /**
     * @notice Removes a teller.
     * Can only be called by the current owner.
     * @param teller The teller to remove.
     */
    #[storage(read, write)]
    fn remove_teller(teller: Address) -> bool {
        validate_owner();
        let is_removed = storage.is_teller.remove(teller);
        is_removed
    }

    /***************************************
    FUND MANAGEMENT FUNCTIONS
    ***************************************/

    /**
     * @notice Sends PIDA to the teller.
     * Can only be called by tellers.
     * @param amount The amount of PIDA to send.
     */
    #[storage(read)]
    fn pull_pida(amount: u64) {
        let sender = get_msg_sender_address_or_panic();
        // check that caller is a registered teller
        require(storage.is_teller.get(sender).unwrap() == true, Error::NotTeller);
        // mint new PIDA
        let pida_call = abi(PIDA, storage.pida.value);
        pida_call.mint(amount);
    }

}


