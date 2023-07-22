contract;

mod events;
mod structs;

use std::constants::ZERO_B256;
use std::assert::*;
use std::storage::*;

use events::*;
use structs::*;
use token_abi::*;
use registry_abi::*;

storage {
    registry: ContractId = ContractId { value: ZERO_B256 },
    pida: ContractId = ContractId { value: ZERO_B256 },
    acp: ContractId = ContractId { value: ZERO_B256 },
    premium_pool: ContractId = ContractId { value: ZERO_B256 },
    paused: bool = false,
    token_info: StorageMap<ContractId, TokenInfo> = StorageMap {},
    index_to_token: StorageMap<u64, ContractId> = StorageMap {},
    products: StorageVec<ContractId> = StorageVec {},
    tokens_length: u64 = 0,
}

#[storage(read)]
fn while_unpaused() {
    assert(!storage.paused);
}

fn pow(num: u64, exponent: u8) -> u64 {
    asm(r1: num, r2: exponent, r3) {
        exp r3 r1 r2;
        r3: u64
    }
}

#[storage(write)]
fn set_registry_internal(registry: ContractId) {
    assert(registry != ContractId::from(ZERO_B256));
    storage.registry = registry;
    
    let reg = abi(Registry, registry.value);
   
    // set acp
    let (_, acp_addr) = reg.try_get("acp                 ");
    assert(acp_addr != ContractId::from(ZERO_B256));
    storage.acp = acp_addr;

    // set pida
    let (_, pida_addr) = reg.try_get("pida                ");
    assert(pida_addr != ContractId::from(ZERO_B256));
    storage.pida = pida_addr;

    let (_, premium_pool_addr) = reg.try_get("premiumPool         ");
    assert(premium_pool_addr != ContractId::from(ZERO_B256));
    storage.premium_pool = premium_pool_addr;

    log(
        RegistrySet {
            registry: registry,
        }
    );
}

fn convert_decimals(amount_in: u64, token_in: ContractId, token_out: ContractId) -> u64 {
    // fetch decimals
    let dec_in = abi(FRC20, token_in.value).decimals();
    let dec_out = abi(FRC20, token_out.value).decimals();
    // convert
    if (dec_in < dec_out) {
        return amount_in * pow(10, (dec_out - dec_in)); // upscale
    } else if (dec_in > dec_out) {
        return amount_in / pow(10, (dec_in - dec_out)); // downscale
    } else {
        return amount_in; // equal
    }
}

abi MyContract {
    fn test_function() -> bool;
}

impl MyContract for Contract {
    fn test_function() -> bool {
        true
    }
}
