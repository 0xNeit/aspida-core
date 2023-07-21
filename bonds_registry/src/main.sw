contract;

mod events;

use std::contract_id::ContractId;
use std::constants::ZERO_B256;
use std::address::Address;
use std::storage::*;
use std::auth::{AuthError, msg_sender};

use token_abi::*;
use bond_registry_abi::*;
use events::*;

storage {
    pida: ContractId = ContractId {
        value: ZERO_B256,
    },
    is_teller: StorageMap<Identity, bool> = StorageMap {},
    owner: Address = Address {
        value: ZERO_B256,
    },
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

impl BondsRegistry for Contract {

    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId) {
        assert(storage.pida.value == ZERO_B256);
        assert(storage.owner.value == ZERO_B256);
        storage.pida = pida;
        storage.owner = owner;
    }

    /***************************************
    TELLER MANAGEMENT FUNCTIONS
    ***************************************/

    #[storage(read, write)]
    fn add_teller(teller: Identity) {
        validate_owner();
        storage.is_teller.insert(teller, true);

        log(
            TellerAdded {
                teller: teller,
            }
        );
    }

    #[storage(read, write)]
    fn remove_teller(teller: Identity) -> bool {
        validate_owner();
        let is_removed = storage.is_teller.remove(teller);

        log(
            TellerRemoved {
                teller: teller,
            }
        );

        return is_removed;
    }

    /***************************************
    FUND MANAGEMENT FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn pull_pida(amount: u64) {
        let sender = msg_sender().unwrap();
        // check that caller is a registered teller
        assert(storage.is_teller.get(sender).unwrap() == true);
        // mint new PIDA
        let pida_call = abi(PIDA, storage.pida.value);
        pida_call.mint(amount);
    }

}


