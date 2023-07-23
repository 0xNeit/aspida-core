contract;

mod events;
mod structs;

use std::constants::ZERO_B256;
use std::assert::*;
use std::storage::*;
use std::b512::B512;
use std::token::*;

use events::*;
use structs::*;
use token_abi::*;
use executor_abi::*;
use registry_abi::*;
use cover_points_abi::*;
use premium_pool_abi::*;

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
    executor: ContractId = ContractId { value: ZERO_B256 },
}

/***************************************
    INTERNAL FUNCTIONS
***************************************/

fn as_address(to: Identity) -> Option<Address> {
    match to {
        Identity::Address(addr) => Option::Some(addr),
        Identity::ContractId(_) => Option::None,
    }
}

fn max(a: u64, b: u64) -> u64 {
    let mut answer: u64 = 0;
    if (a > b) {
        answer = a;
    } else {
        answer = b;
    }

    answer
}

#[storage(read)]
fn while_unpaused() {
    assert(storage.paused == false);
}

fn pow(num: u64, exponent: u8) -> u64 {
    asm(r1: num, r2: exponent, r3) {
        exp r3 r1 r2;
        r3: u64
    }
}

#[storage(read)]
fn get_refundable_pida_amount(
        depositor: Identity,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) -> u64 {
        // check price
        assert(abi(Executor, storage.executor.value).verify_price(storage.pida, price, price_deadline, signature));
        let acp = abi(ACP, storage.acp.value);
        let acp_balance = acp.balance_of(depositor);
        let min_required_acp = acp.min_acp_required(as_address(depositor).unwrap());
        let nr_acp_balance = acp.balance_of_non_refundable(depositor);
        let non_refundable_acp =  max(min_required_acp, nr_acp_balance);
        let mut refundable_acp_balance = 0;
        if (acp_balance > non_refundable_acp) {
            refundable_acp_balance = acp_balance - non_refundable_acp;
        } else {
            refundable_acp_balance = 0;
        };

        let mut pida_amount = 0;
        if (refundable_acp_balance > 0) {
            pida_amount = refundable_acp_balance * pow(10, 18u8) / price;
        } else {
            pida_amount = 0;
        };

        return pida_amount;
}

#[storage(read)]
fn deposit_stable_internal(
    token: ContractId,
    from: Identity,
    recipient: Identity,
    amount: u64,
) {
  // checks
  let ti = storage.token_info.get(token).unwrap();
  assert(ti.accepted);
  assert(ti.stable);

  // interactions
  let acp_amount = convert_decimals(amount, token, storage.acp);
  abi(PremiumPool, storage.premium_pool.value).withdraw(amount, token, from);
  abi(ACP, storage.acp.value).mint(recipient, acp_amount, ti.refundable);

  log(
        TokenDeposited {
            token: token, 
            depositor: from, 
            receiver: recipient, 
            amount: amount,
        }
  );
}

#[storage(read)]
fn deposit_non_stable_internal(
    token: ContractId,
    from: Identity,
    recipient: Identity,
    amount: u64,
    price: u64,
    price_deadline: u64,
    signature: B512,
) {
    // checks
    let ti = storage.token_info.get(token).unwrap();
    assert(ti.accepted);
    assert(!ti.stable);
    assert(abi(Executor, storage.executor.value).verify_price(token, price, price_deadline, signature));

    // interactions
    let acp_amount = (amount * price) / pow(10, 18u8);
    abi(PremiumPool, storage.premium_pool.value).withdraw(amount, token, from);
    abi(ACP, storage.pida.value).mint(recipient, acp_amount, true);

    log(
        TokenDeposited {
            token: token, 
            depositor: from, 
            receiver: recipient, 
            amount: amount,
        }
    );
}

#[storage(read)]
fn withdraw_internal(
    from: Identity,
    amount: u64,
    recipient: Identity,
    price: u64,
    price_deadline: u64,
    signature: B512,
) {
    assert(amount > 0);
    assert(abi(Executor, storage.executor.value).verify_price(storage.pida, price, price_deadline, signature));
    let refundable_pida_amount = get_refundable_pida_amount(from, price, price_deadline, signature);
    assert(amount <= refundable_pida_amount);

    let acp_amount = (amount * price) / pow(10, 18u8);
    abi(ACP, storage.acp.value).withdraw(from, acp_amount);
    abi(PremiumPool, storage.premium_pool.value).withdraw(amount, storage.pida, recipient);
    
    log(
        TokenWithdrawn {
            depositor: from, 
            receiver: recipient, 
            amount: amount,
        }
    );
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
