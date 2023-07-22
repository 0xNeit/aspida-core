contract;

mod events;
mod structs;

use std::constants::ZERO_B256;
use std::assert::*;
use std::storage::*;

use events::*;
use structs::*;

storage {
    registry: ContractId = ContractId { value: ZERO_B256 },
    pida: ContractId = ContractId { value: ZERO_B256 },
    acp: ContractId = ContractId { value: ZERO_B256 },
    premium_pool: Address = Address { value: ZERO_B256 },
    paused: bool = false,
    token_info: StorageMap<ContractId, TokenInfo> = StorageMap {},
    index_to_token: StorageMap<u64, ContractId> = StorageMap {},
    products: StorageVec<ContractId> = StorageVec {},
    tokens_length: u64 = 0,
}

abi MyContract {
    fn test_function() -> bool;
}

impl MyContract for Contract {
    fn test_function() -> bool {
        true
    }
}
