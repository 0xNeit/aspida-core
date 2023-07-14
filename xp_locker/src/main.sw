contract;

use std::constants::*;

abi Locker {
    #[storage(write)]
    fn initialize(owner: Address, pida: ContractId);
}

pub struct Lock {
    amount: u64,
    end: u64,
}

pub enum Errors {
    ZeroAddress: (),
}

storage {
    pida: ContractId = ContractId {
        value: ZERO_B256,
    },
    owner: Address = Address {
        value: ZERO_B256,
    },
    total_num_locks: u64 = 0,
    locks: StorageMap<u64, Lock> = StorageMap {},
}

const MAX_LOCK_DURATION: u64 = 126_144_000;

impl Locker for Contract {

    #[storage(write)]
    fn initialize(owner: Address, pida: ContractId) {
        require(pida != ContractId::from(ZERO_B256), Errors::ZeroAddress);
        storage.pida = pida;
    }   
}
