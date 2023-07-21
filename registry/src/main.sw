contract;

use std::constants::ZERO_B256;
use std::assert::*;
use std::auth::*;

use registry_abi::Registry;

pub struct RegistryEntry {
    index: u64,
    value: ContractId,
}

/// Emitted when a record is set.
pub struct RecordSet {
    key: str[20], 
    value: ContractId,
}

storage {
    ids: StorageMap<str[20], RegistryEntry> = StorageMap {}, // contract name => contract ids
    keys: StorageMap<u64, str[20]> = StorageMap {},          // index => key
    length: u64 = 0,                                         // The number of unique keys.
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

impl Registry for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    /**
     * @notice Gets the `value` of a given `key`.
     * Reverts if the key is not in the mapping.
     * @param key The key to query.
     * @return value The value of the key.
    */
    #[storage(read)]
    fn get(key: str[20]) -> ContractId {
        let entry = storage.ids.get(key).unwrap();
        assert(entry.index != 0);
        entry.value
    }

    /**
     * @notice Gets the `value` of a given `key`.
     * Fails gracefully if the key is not in the mapping.
     * @param key The key to query.
     * @return success True if the key was found, false otherwise.
     * @return value The value of the key or zero if it was not found.
    */
    #[storage(read)]
    fn try_get(key: str[20]) -> (bool, ContractId) {
        let entry = storage.ids.get(key).unwrap();
        let mut tuple = (false, ContractId::from(ZERO_B256));
        if (entry.index == 0) {
            tuple = (false, ContractId::from(ZERO_B256));
        } else {
            tuple = (true, entry.value);
        }
        tuple
    }

    /**
     * @notice Gets the `key` of a given `index`.
     * @dev Iterable [1,length].
     * @param index The index to query.
     * @return key The key at that index.
    */
    #[storage(read)]
    fn get_key(index: u64) -> str[20] {
        assert(index != 0 && index <= storage.length);
        let key = storage.keys.get(index).unwrap();
        key
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Sets keys and values.
     * Can only be called by the current owner.
     * @param keys The keys to set.
     * @param values The values to set.
    */
    #[storage(read, write)]
    fn set(keys: Vec<str[20]>, values: Vec<ContractId>) {
        validate_owner();
        let len = keys.len();
        assert(len == values.len());
        let mut i = 0;
        while (i < len) {
            assert(values.get(i).unwrap() != ContractId::from(ZERO_B256));
            let key = keys.get(i).unwrap();
            let value = values.get(i).unwrap();
            let mut entry = storage.ids.get(key).unwrap();
            // add new record
            if (entry.index == 0) {
                entry.index = storage.length + 1; // auto increment from 1
                storage.keys.insert(entry.index, key); 
            }

            // store record
            entry.value = value;
            storage.ids.insert(key, entry);

            log(
                RecordSet {
                    key: key,
                    value: value,
                }
            );

            i = i + 1;
        }   
    }
}
