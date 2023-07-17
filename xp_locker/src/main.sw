contract;

mod events;

use std::constants::*;
use std::block::*;
use std::auth::msg_sender;
use std::token::*;
use std::storage::*;
use std::auth::*;
use std::vec::*;

use nft::{
    balance_of,
    mint,
    owner_of,
    tokens_minted,
};

use nft::extensions::token_metadata::*;

use events::*;

use token_abi::PIDA;
use locker_abi::Locker;

use reentrancy::*;

pub struct Lock {
    amount: u64,
    end: u64,
}

pub enum Errors {
    NotInitialized: (),
    OutOfBounds: (),
    ZeroAddress: (),
    ExceedMaxLock: (),
}

pub struct LockMeta {
    name: str[10],
    symbol: str[6],
}

pub struct IndexMap {
    index: u64,
    token_id: u64,
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
    owned_tokens: StorageMap<Address, IndexMap> = StorageMap {},
    xp_lock_listeners: StorageVec<ContractId> = StorageVec {},
}

const MAX_LOCK_DURATION: u64 = 126_144_000;

/***************************************
    HELPER FUNCTIONS
***************************************/

fn as_address(to: Identity) -> Option<Address> {
    match to {
        Identity::Address(addr) => Option::Some(addr),
        Identity::ContractId(_) => Option::None,
    }
}

/**
    * @notice Creates a new lock.
    * @param recipient The user that the lock will be minted to.
    * @param amount The amount of PIDA in the lock.
    * @param end The end of the lock.
    * @param xp_lock_id The ID of the new lock.
*/
#[storage(read, write)]
fn _create_lock(
    recipient: Identity, 
    amount: u64, 
    end: u64
) -> u64 {
    let new_lock = Lock {
        amount: amount,
        end: end,
    };

    require(new_lock.end <= timestamp() + MAX_LOCK_DURATION, Errors::ExceedMaxLock);
    // accounting
    mint(amount, recipient);

    let mut xp_lock_id = tokens_minted() - amount;
    let meta = LockMeta {
        name: "xPIDA Lock",
        symbol: "xpLOCK"
    };

    while xp_lock_id < tokens_minted() {
        set_token_metadata(Option::Some(meta), xp_lock_id);
        xp_lock_id += 1;
    }
    storage.locks.insert(xp_lock_id, new_lock);
    let mut tnl = storage.total_num_locks;
    tnl = xp_lock_id;
    storage.total_num_locks = tnl;

    add_token_to_owner_enumeration(as_address(recipient).unwrap(), xp_lock_id);

    log(
        LockCreated {
            xp_lock_id: xp_lock_id,
        }
    );
    xp_lock_id
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
    require(exists(token_id) == true, Errors::NotInitialized);
}

/**
    * @notice Information about a lock.
    * @param xp_lock_id The ID of the lock to query.
    * @return lock_ Information about the lock.
*/
#[storage(read)]
fn locks(xp_lock_id: u64) -> Lock {
    token_exists(xp_lock_id);
    storage.locks.get(xp_lock_id).unwrap()
}

/**
    * @notice Determines if the lock is locked.
    * @param xp_lock_id The ID of the lock to query.
    * @return locked True if the lock is locked, false if unlocked.
*/
#[storage(read)]
fn is_locked(xp_lock_id: u64) -> bool {
    token_exists(xp_lock_id);
    let locks = storage.locks.get(xp_lock_id).unwrap();
    locks.end > timestamp()
}

/**
    * @notice Determines the time left until the lock unlocks.
    * @param xsLockID The ID of the lock to query.
    * @return time The time left in seconds, 0 if unlocked.
*/
#[storage(read)]
fn time_left(xp_lock_id: u64) -> u64 {
    let mut time = 0;
    token_exists(xp_lock_id);
    let locks = storage.locks.get(xp_lock_id).unwrap();
    if ((locks.end > timestamp()) == true) {
        time = locks.end - timestamp(); // locked
    } else {
        time = 0; // unlocked
    }
    time
}

#[storage(read)]
fn token_of_owner_by_index(owner: Address, index: u64) -> u64 {
    require(index < balance_of(Identity::Address(owner)), Errors::OutOfBounds);
    let outer_map = storage.owned_tokens.get(owner).unwrap();
    let inner_map = outer_map.token_id;
    inner_map
}

#[storage(read, write)]
fn add_token_to_owner_enumeration(to: Address, token_id: u64) {
    let length = balance_of(Identity::Address(to));
    let map = IndexMap {
        index: length,
        token_id: token_id,
    };

    storage.owned_tokens.insert(to, map);

}

/**
    * @notice Returns the amount of PIDA the user has staked.
    * @param account The account to query.
    * @return balance The user's balance.
*/
#[storage(read)]
fn staked_balance(account: Address) -> u64 {
    let num_of_locks = balance_of(Identity::Address(account));
    let mut balance = 0;
    let mut i = 0;
    while (i < num_of_locks) {
        let xp_lock_id = token_of_owner_by_index(account, i);
        balance += storage.locks.get(xp_lock_id).unwrap().amount;
        i = i + 1;
    };

    balance
}

/**
    * @notice The list of contracts that are listening to lock updates.
    * @return listeners_ The list as an array.
*/
#[storage(read)]
fn get_xp_lock_listeners() -> Vec<ContractId> {
    let len = storage.xp_lock_listeners.len();
    let mut listeners = Vec::new();
    let mut index = 0;
    while ( index < len) {
        listeners.push(storage.xp_lock_listeners.get(index).unwrap());
        index = index + 1;
    };

    listeners
}

impl Locker for Contract {

    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId) {
        require(pida != ContractId::from(ZERO_B256), Errors::ZeroAddress);
        require(owner != Address::from(ZERO_B256), Errors::ZeroAddress);
        require(storage.owner == Address::from(ZERO_B256), Errors::NotInitialized);
        storage.pida = pida;
        storage.owner = owner;
    }

    /***************************************
    MUTATOR FUNCTIONS
    ***************************************/

    /**
     * @notice Deposit PIDA to create a new lock.
     * @dev PIDA is transferred from msg_sender().
     * @dev use end=0 to initialize as unlocked.
     * @param recipient The account that will receive the lock.
     * @param amount The amount of PIDA to deposit.
     * @param end The timestamp the lock will unlock.
     * @return xp_lock_id The ID of the newly created lock.
    */
    #[storage(read, write)]
    fn create_lock(
        recipient: Identity, 
        amount: u64, 
        end: u64
    ) -> u64 {
        reentrancy_guard();
        let sender = get_msg_sender_address_or_panic();
        // pull pida
        transfer_to_address(
            amount, 
            ContractId::from(get::<b256>(storage.pida.value).unwrap()),
            sender
        );
        // accounting
        let new_lock = _create_lock(recipient, amount, end);
        
        new_lock
    }  
}
