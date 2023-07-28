contract;

use std::constants::ZERO_B256;
use std::block::*;

use locker_abi::*;

use nft::{
    balance_of,
};

storage {
    owner: Address = Address { value: ZERO_B256 },
    xp_locker: ContractId = ContractId { value: ZERO_B256 },
}

const MAX_LOCK_DURATION: u64 = 126_144_000; // 4 years in seconds
const MAX_LOCK_MULTIPLIER_BPS: u64 = 40000; // 4x
const UNLOCKED_MULTIPLIER_BPS: u64 = 10000; // 1x
const MAX_BPS: u64 = 10000;

#[storage(read)]
fn balance_of_lock(xp_lock_id: u64) -> u64 {
    let locker = abi(Locker, storage.xp_locker.value);
    let lock = locker.locks(xp_lock_id);
    let base = lock.amount * UNLOCKED_MULTIPLIER_BPS / MAX_BPS;
    
    let mut bonus = 0;

    if (lock.end <= timestamp()) {
        bonus = 0; // unlocked
    } else {
        bonus = lock.amount * (lock.end - timestamp()) * (MAX_LOCK_MULTIPLIER_BPS - UNLOCKED_MULTIPLIER_BPS) / (MAX_LOCK_DURATION * MAX_BPS); // locked
    }

    return base + bonus;
}


abi VePida {
    #[storage(read, write)]
    fn initialize(owner: Address, xp_locker: ContractId);

    #[storage(read)]
    fn balance_of(account: Identity) -> u64;

    #[storage(read)]
    fn total_supply() -> u64; 

    fn name() -> str[18];

    fn symbol() -> str[6];

    fn decimals() -> u8;
}

impl VePida for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address, xp_locker: ContractId) {
        assert(xp_locker != ContractId::from(ZERO_B256));
        
        let mut owner_store = storage.owner;
        let mut xp_store = storage.xp_locker;

        owner_store = owner;
        xp_store = xp_locker;

        storage.owner = owner_store;
        storage.xp_locker = xp_store;
    }

    /***************************************
    VIEW fnS
    ***************************************/

    #[storage(read)]
    fn balance_of(account: Identity) -> u64 {
        let locker = abi(Locker, storage.xp_locker.value);
        let num_of_locks = locker.balance_of(account);
        let mut balance = 0;
        let mut i = 0;

        while (i < num_of_locks) {
            let xp_lock_id = locker.token_of_owner_by_index(account, i);
            balance += balance_of_lock(xp_lock_id);
            i += 1;
        };

        return balance;
    }

    #[storage(read)]
    fn total_supply() -> u64 {
        let locker = abi(Locker, storage.xp_locker.value);
        let num_of_locks = locker.total_supply();
        let mut supply = 0;
        let mut i = 0;
        while (i < num_of_locks) {
            let xp_lock_id = locker.token_by_index(i);
            supply += balance_of_lock(xp_lock_id);
            i += 1;
        };

        return supply;
    }

    fn name() -> str[18] {
        return "Voting Escrow Pida";
    }

    
    fn symbol() -> str[6] {
        return "vePIDA";
    }

    
    fn decimals() -> u8 {
        return 18u8;
    }
}
