contract;

mod events;

use std::constants::*;
use std::assert::*;
use std::block::*;
use std::auth::msg_sender;
use std::token::*;
use std::storage::*;
use std::auth::*;
use std::vec::*;
use std::call_frames::*;

use nft::{
    balance_of,
    is_approved_for_all,
    mint,
    owner_of,
    approved,
    tokens_minted,
};

use nft::extensions::token_metadata::*;

use nft::extensions::burnable::*;

use events::*;

use token_abi::PIDA;
use locker_abi::{ Lock, Locker };
use staking_abi::*;

use reentrancy::*;

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
    listeners_map: StorageMap<ContractId, u64> = StorageMap {},
    base_uri: str[32] = "                                ",
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

pub fn as_contract_id(to: Identity) -> Option<ContractId> {
    match to {
        Identity::Address(_) => Option::None,
        Identity::ContractId(id) => Option::Some(id),
    }
}

#[storage(read)]
fn is_approved_or_owner(spender: Identity, token_id: u64) -> bool {
    let owner = owner_of(token_id).unwrap();
    (spender == owner || is_approved_for_all(spender, owner) || approved(token_id).unwrap() == spender)
}

/**
    * @notice Creates a new lock.
    * @param recipient The user that the lock will be minted to.
    * @param amount The amount of PIDA in the lock.
    * @param end The end of the lock.
    * @param xp_lock_id The ID of the new lock.
*/
#[storage(read, write)]
fn create_lock_internal(
    recipient: Identity, 
    amount: u64, 
    end: u64
) -> u64 {
    let new_lock = Lock {
        amount: amount,
        end: end,
    };

    assert(new_lock.end <= timestamp() + MAX_LOCK_DURATION);
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

    let empty_lock = Lock {
        amount: 0,
        end: 0,
    };

    let mut tnl = storage.total_num_locks;
    tnl = xp_lock_id;
    storage.total_num_locks = tnl;

    add_token_to_owner_enumeration(as_address(recipient).unwrap(), xp_lock_id);

    notify_internal(
        xp_lock_id, 
        Address::from(ZERO_B256),
        as_address(recipient).unwrap(),
        empty_lock,
        new_lock,
    );

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
fn validate_owner() {
    let sender = get_msg_sender_address_or_panic();
    assert(storage.owner == sender);
}

#[storage(read)]
fn exists_internal(token_id: u64) -> bool {
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
    assert(exists_internal(token_id) == true);
}

/**
    * @notice Information about a lock.
    * @param xp_lock_id The ID of the lock to query.
    * @return lock_ Information about the lock.
*/
#[storage(read)]
fn locks_internal(xp_lock_id: u64) -> Lock {
    token_exists(xp_lock_id);
    storage.locks.get(xp_lock_id).unwrap()
}

/**
    * @notice Determines if the lock is locked.
    * @param xp_lock_id The ID of the lock to query.
    * @return locked True if the lock is locked, false if unlocked.
*/
#[storage(read)]
fn is_locked_internal(xp_lock_id: u64) -> bool {
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
fn time_left_internal(xp_lock_id: u64) -> u64 {
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

/**
    * @notice Returns the amount of PIDA the user has staked.
    * @param account The account to query.
    * @return balance The user's balance.
*/
#[storage(read)]
fn staked_balance_internal(account: Address) -> u64 {
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
fn get_xp_lock_listeners_internal() -> Vec<ContractId> {
    let len = storage.xp_lock_listeners.len();
    let mut listeners = Vec::new();
    let mut index = 0;
    while (index < len) {
        listeners.push(storage.xp_lock_listeners.get(index).unwrap());
        index = index + 1;
    };

    listeners
}

#[storage(read)]
fn token_of_owner_by_index(owner: Address, index: u64) -> u64 {
    assert(index < balance_of(Identity::Address(owner)));
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

#[storage(read)]
fn notify_internal(
    xp_lock_id: u64,
    old_owner: Address,
    new_owner: Address,
    old_lock: Lock,
    new_lock: Lock,
) {
    // register action with listener
    let len = storage.xp_lock_listeners.len();
    let mut i = 0;
    while (i < len) {
        let listener_id = storage.xp_lock_listeners.get(i).unwrap();
        let listener_abi = abi(Staking, ContractId::into(listener_id));
        listener_abi.register_lock_event(
            xp_lock_id,
            old_owner,
            new_owner,
            old_lock,
            new_lock,
        );
        i = i + 1;
    }
}

#[storage(read, write)]
fn update_lock(xp_lock_id: u64, amount: u64, end: u64) {
    // checks
    let prev_lock = storage.locks.get(xp_lock_id).unwrap();
    let new_lock = Lock {
        amount: amount,
        end: end,
    };

    // accounting
    storage.locks.insert(xp_lock_id, new_lock);
    let owner = as_address(owner_of(xp_lock_id).unwrap()).unwrap();
    notify_internal(xp_lock_id, owner, owner, prev_lock, new_lock);

    log(
        LockUpdated {
            xp_lock_id: xp_lock_id,
            amount: amount,
            end: new_lock.end,
        }
    );
}

#[storage(read, write)]
fn withdraw_internal(xp_lock_id: u64, amount: u64) {
    assert(storage.locks.get(xp_lock_id).unwrap().end <= timestamp());

    if (amount == storage.locks.get(xp_lock_id).unwrap().amount) {
        let deleted_meta: Option<LockMeta> = Option::None;
        set_token_metadata(deleted_meta, xp_lock_id);
        burn(xp_lock_id);
        let _ = storage.locks.remove(xp_lock_id);
    } else {
        let old_lock = storage.locks.get(xp_lock_id).unwrap();
        let new_lock = Lock {
            amount: old_lock.amount - amount,
            end: old_lock.end
        };
        storage.locks.insert(xp_lock_id, new_lock);

        let owner =  as_address(owner_of(xp_lock_id).unwrap()).unwrap();
        notify_internal(xp_lock_id, owner, owner, old_lock, new_lock);
    }

    log(
        Withdraw {
            xp_lock_id: xp_lock_id,
            amount: amount,        
        }
    );
}

impl Locker for Contract {

    #[storage(read, write)]
    fn initialize(owner: Address, pida: ContractId) {
        assert(pida != ContractId::from(ZERO_B256));
        assert(owner != Address::from(ZERO_B256));
        assert(storage.owner == Address::from(ZERO_B256));
        storage.pida = pida;
        storage.owner = owner;
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn exists(token_id: u64) -> bool {
        return exists_internal(token_id);
    }

    #[storage(read)]
    fn locks(xp_lock_id: u64) -> Lock {
        return locks_internal(xp_lock_id);
    }

    #[storage(read)]
    fn is_locked(xp_lock_id: u64) -> bool {
        return is_locked_internal(xp_lock_id);
    }

    #[storage(read)]
    fn time_left(xp_lock_id: u64) -> u64 {
        return time_left_internal(xp_lock_id);
    }

    #[storage(read)]
    fn staked_balance(account: Address) -> u64 {
        return staked_balance_internal(account);
    }

    #[storage(read)]
    fn get_xp_lock_listeners() -> Vec<ContractId> {
        return get_xp_lock_listeners_internal();
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
        // pull pida
        transfer(
            amount, 
            storage.pida,
            Identity::ContractId(contract_id())
        );
        // accounting
        let new_lock = create_lock_internal(recipient, amount, end);
        
        new_lock
    }

    #[storage(read, write)]
    fn increase_amount(xp_lock_id: u64, amount: u64) {
        reentrancy_guard();
        // pull pida
        transfer(amount, storage.pida, Identity::ContractId(contract_id()));
        // accounting
        let new_amount = storage.locks.get(xp_lock_id).unwrap().amount + amount;
        update_lock(xp_lock_id, new_amount, storage.locks.get(xp_lock_id).unwrap().end);
    }

    #[storage(read, write)]
    fn extend_lock(xp_lock_id: u64, end: u64) {
        reentrancy_guard();

        let sender = msg_sender().unwrap();
        assert(is_approved_or_owner(sender, xp_lock_id));

        assert(end <= timestamp() + MAX_LOCK_DURATION);
        assert(storage.locks.get(xp_lock_id).unwrap().end <= end);
        update_lock(xp_lock_id, storage.locks.get(xp_lock_id).unwrap().amount, end);
    }

    #[storage(read, write)]
    fn withdraw(xp_lock_id: u64, recipient: Identity) {
        reentrancy_guard();

        let sender = msg_sender().unwrap();
        assert(is_approved_or_owner(sender, xp_lock_id));

        let amount = storage.locks.get(xp_lock_id).unwrap().amount;
        withdraw_internal(xp_lock_id, amount);

        // transfer pida
        transfer(amount, storage.pida, recipient);
    }

    #[storage(read, write)]
    fn withdraw_in_part(xp_lock_id: u64, recipient: Identity, amount: u64) {
        reentrancy_guard();

        let sender = msg_sender().unwrap();
        assert(is_approved_or_owner(sender, xp_lock_id));

        assert(amount <= storage.locks.get(xp_lock_id).unwrap().amount);
        withdraw_internal(xp_lock_id, amount);

        // transfer pida
        transfer(amount, storage.pida, recipient);
    }

    #[storage(read, write)]
    fn withdraw_many(xp_lock_ids: Vec<u64>, recipient: Identity) {
        reentrancy_guard();

        let sender = msg_sender().unwrap();
        let len = xp_lock_ids.len();
        let mut amount = 0;
        let mut i = 0;

        while (i < len) {
            let xp_lock_id = xp_lock_ids.get(i).unwrap();
            assert(is_approved_or_owner(sender, xp_lock_id));
            let new_amount = storage.locks.get(xp_lock_id).unwrap().amount;
            amount = amount + new_amount;
            withdraw_internal(xp_lock_id, new_amount);
            i = i + 1;
        };

        // transfer pida
        transfer(amount, storage.pida, recipient);
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Adds a listener.
     * Can only be called by the current owner.
     * @param listener The listener to add.
    */
    #[storage(read, write)]
    fn add_xp_lock_listener(listener: ContractId) {
        validate_owner();
        let index = storage.xp_lock_listeners.len();
        storage.xp_lock_listeners.push(listener);

        storage.listeners_map.insert(listener, index);

        log(
            XpLockListenerAdded {
                listener: listener
            }
        );
    }

    /**
     * @notice Removes a listener.
     * Can only be called by the current owner.
     * @param listener The listener to remove.
    */
    #[storage(read, write)]
    fn remove_xp_lock_listener(listener: ContractId) -> bool {
        validate_owner();

        let listener_index = storage.listeners_map.get(listener).unwrap();
        let removed_listener = storage.xp_lock_listeners.remove(listener_index);
        let removed_map = storage.listeners_map.remove(removed_listener);
        
        log(
            XpLockListenerRemoved {
                listener: removed_listener
            }
        );

        removed_map
    }

    /**
     * @notice Sets the base URI for computing `tokenURI`.
     * Can only be called by the current owner.
     * @param baseURI The new base URI.
    */
    #[storage(read, write)]
    fn set_base_uri(base_uri: str[32]) {
        validate_owner();
        let mut uri = storage.base_uri;
        uri = base_uri;
        storage.base_uri = uri;
    }  
}
