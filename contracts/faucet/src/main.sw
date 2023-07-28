contract;

use std::constants::ZERO_B256;
use std::storage::*;
use std::auth::*;
use std::block::*;

use token_abi::*;

storage {
    pida: ContractId = ContractId { value: ZERO_B256 },
    last_pull: StorageMap<Address, u64> = StorageMap {},
}

pub fn get_msg_sender_address_or_panic() -> Address {
    let sender: Result<Identity, AuthError> = msg_sender();

    if let Identity::Address(address) = sender.unwrap() {
        address
    } else {
        revert(0);
    }
}

abi MyContract {
    #[storage(read, write)]
    fn initialize(pida: ContractId);

    #[storage(read, write)]
    fn drip();
}

impl MyContract for Contract {
    #[storage(read, write)]
    fn initialize(pida: ContractId) {
        let mut pida_store = storage.pida;
        pida_store = pida;
        storage.pida = pida_store;
    }

    #[storage(read, write)]
    fn drip() {
        let sender = get_msg_sender_address_or_panic();

        assert(storage.last_pull.get(sender).unwrap() + 86400 <= timestamp());
        storage.last_pull.insert(sender, timestamp());
        abi(FRC20, storage.pida.value).mint_to(sender, 10000);
    }
}
