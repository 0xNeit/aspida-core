contract;

mod events;

use std::constants::ZERO_B256;
use std::storage::*;
use std::auth::*;

use events::*;
use reentrancy::*;
use data_provider_abi::*;

storage {
    owner: Address = Address {
        value: ZERO_B256,
    },
    uwp_balance_of: StorageMap<str[20], u64> = StorageMap {},
    index_to_uwp: StorageMap<u64, str[20]> = StorageMap {},
    uwp_to_index: StorageMap<str[20], u64> = StorageMap {},
    updaters: StorageMap<Identity, u64> = StorageMap {},
    updaters_vec: StorageVec<Identity> = StorageVec {},
    num_of_pools: u64 = 0,
    max_cover: u64 = 0,
}

fn get_msg_sender_address_or_panic() -> Address {
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

fn as_address(to: Identity) -> Option<Address> {
    match to {
        Identity::Address(addr) => Option::Some(addr),
        Identity::ContractId(_) => Option::None,
    }
}

#[storage(read)]
fn is_updater_internal(account: Identity) -> bool {
    if (storage.updaters.get(account).is_none()) {
        return false;
    } else {
        return true;
    }
}

#[storage(read)]
fn can_update() {
    let sender = msg_sender().unwrap();
    assert(as_address(sender).unwrap() == storage.owner || is_updater_internal(sender));
}

#[storage(read, write)]
fn set_internal(uwp_names: Vec<str[20]>, amounts: Vec<u64>) {
    // delete current underwriting pools
    let pool_count = storage.num_of_pools;
    let mut uwp_name = "                    ";
    let mut i1 = pool_count;

    while (i1 > 0) {
        uwp_name = storage.index_to_uwp.get(i1).unwrap();
        let _ = storage.uwp_to_index.remove(uwp_name);
        let _ = storage.index_to_uwp.remove(i1);
        let _ = storage.uwp_balance_of.remove(uwp_name);

        log(UnderwritingPoolRemoved {
            uwp_name: uwp_name,
        });

        i1 = i1 - 1;
    };

    // set new underwriting pools
    let mut cover = 0;
    storage.num_of_pools = 0;
    let mut amount = 0;
    let mut i = 0;
    while (i < uwp_names.len()) {
        uwp_name = uwp_names.get(i).unwrap();
        amount = amounts.get(i).unwrap();
        cover += amount;

        storage.uwp_balance_of.insert(uwp_name, amount);
        if (storage.uwp_to_index.get(uwp_name).unwrap() == 0) {
            let index = storage.num_of_pools;
            storage.uwp_to_index.insert(uwp_name, (index + 1));
            storage.index_to_uwp.insert(index, uwp_name);
            storage.num_of_pools = index;
        };

        log(UnderwritingPoolSet {
            uwp_name: uwp_name,
            amount: amount,
        });
        i += 1;
    }
    storage.max_cover = cover;
}

#[storage(read, write)]
fn remove_internal(uwp_names: Vec<str[20]>) {
    let mut uwp_name = "                    ";
    let mut cover = storage.max_cover;
    let mut i = 0;
    while (i < uwp_names.len()) {
        uwp_name = uwp_names.get(i).unwrap();
        let index = storage.uwp_to_index.get(uwp_name).unwrap();
        if (index == 0) {
            return;
        };

        let pool_count = storage.num_of_pools;
        if (pool_count == 0) {
            return;
        };

        if (index != pool_count) {
            let last_pool = storage.index_to_uwp.get(pool_count).unwrap();
            storage.uwp_to_index.insert(last_pool, index);
            storage.index_to_uwp.insert(index, last_pool);
        };

        cover -= storage.uwp_balance_of.get(uwp_name).unwrap();
        let _ = storage.uwp_to_index.remove(uwp_name);
        let _ = storage.index_to_uwp.remove(pool_count);
        let _ = storage.uwp_balance_of.remove(uwp_name);

        storage.num_of_pools -= 1;

        log(UnderwritingPoolRemoved {
            uwp_name: uwp_name,
        });

        i = i + 1;
    }

    storage.max_cover = cover;
}

impl DataProvider for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;
    }

    /***************************************
     MUTUATOR FUNCTIONS
    ***************************************/
    #[storage(read, write)]
    fn set(uwp_names: Vec<str[20]>, amounts: Vec<u64>) {
        reentrancy_guard();
        can_update();

        assert(uwp_names.len() == amounts.len());
        set_internal(uwp_names, amounts);
    }

    #[storage(read, write)]
    fn remove(uwp_names: Vec<str[20]>) {
        can_update();
        remove_internal(uwp_names);
    }

    /***************************************
     VIEW FUNCTIONS
    ***************************************/
    #[storage(read)]
    fn max_cover() -> u64 {
        let pools = storage.num_of_pools;
        let mut i = pools;
        let mut cover = 0;
        while (i > 0) {
            let name = storage.index_to_uwp.get(i).unwrap();
            cover += storage.uwp_balance_of.get(name).unwrap();
            i = i - 1;
        }
        return cover;
    }

    #[storage(read)]
    fn balance_of(uwp_name: str[20]) -> u64 {
        let balance = storage.uwp_balance_of.get(uwp_name).unwrap();
        return balance;
    }

    #[storage(read)]
    fn pool_of(index: u64) -> str[20] {
        let pool = storage.index_to_uwp.get(index).unwrap();
        return pool;
    }

    #[storage(read)]
    fn is_updater(updater: Identity) -> bool {
        return is_updater_internal(updater);
    }

    #[storage(read)]
    fn updater_at(index: u64) -> Identity {
        return storage.updaters_vec.get(index).unwrap();
    }

    #[storage(read)]
    fn nums_of_updater() -> u64 {
        return storage.updaters_vec.len();
    }

    /***************************************
     GOVERNANCE FUNCTIONS
    ***************************************/
    #[storage(read, write)]
    fn add_updater(updater: Identity) {
        validate_owner();
        let len = storage.updaters_vec.len();
        storage.updaters.insert(updater, (len + 1));
        storage.updaters_vec.push(updater);

        log(UwpUpdaterSet {
            uwp_updater: updater,
        });
    }

    #[storage(read, write)]
    fn remove_updater(updater: Identity) {
        validate_owner();

        if (!is_updater_internal(updater)) {
            return;
        };

        let index = storage.updaters.get(updater).unwrap();

        let _ = storage.updaters.remove(updater);
        let _ = storage.updaters_vec.remove(index);

        log(UwpUpdaterRemoved {
            uwp_updater: updater,
        });
    }
}
