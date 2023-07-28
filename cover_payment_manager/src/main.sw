contract;

mod events;

use std::constants::ZERO_B256;
use std::assert::*;
use std::storage::*;
use std::b512::B512;
use std::token::*;
use std::auth::*;

use events::*;
use token_abi::*;
use executor_abi::*;
use registry_abi::*;
use cpm_abi::*;
use cover_points_abi::*;
use premium_pool_abi::*;
use reentrancy::*;

storage {
    owner: Address = Address { value: ZERO_B256 },
    registry: ContractId = ContractId { value: ZERO_B256 },
    pida: ContractId = ContractId { value: ZERO_B256 },
    acp: ContractId = ContractId { value: ZERO_B256 },
    premium_pool: ContractId = ContractId { value: ZERO_B256 },
    paused: bool = false,
    token_info: StorageMap<ContractId, TokenInfo> = StorageMap {},
    index_to_token: StorageMap<u64, ContractId> = StorageMap {},
    products: StorageMap<ContractId, u64> = StorageMap {},
    products_vec: StorageVec<ContractId> = StorageVec {},
    products_length: u64 = 0,
    tokens_length: u64 = 0,
    executor: ContractId = ContractId { value: ZERO_B256 },
}

/***************************************
    INTERNAL FUNCTIONS
***************************************/

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

fn as_address(to: Identity) -> Option<Address> {
    match to {
        Identity::Address(addr) => Option::Some(addr),
        Identity::ContractId(_) => Option::None,
    }
}

fn as_contract_id(to: Identity) -> Option<ContractId> {
    match to {
        Identity::Address(_) => Option::None,
        Identity::ContractId(id) => Option::Some(id),
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
        let acp_id = storage.acp.value;
        assert(abi(Executor, storage.executor.value).verify_price(storage.pida, price, price_deadline, signature));
        let acp = abi(ACP, acp_id);
        let acp_balance = acp.balance_of(depositor);
        let min_required_acp = acp.min_acp_required(depositor);
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

    let executor_id = storage.executor.value;
    let pida_contract = storage.pida;
    let acp_id = storage.acp.value;
    let premium_pool_id = storage.premium_pool.value;
    let refundable_pida_amount = get_refundable_pida_amount(from, price, price_deadline, signature);

    assert(abi(Executor, executor_id).verify_price(pida_contract, price, price_deadline, signature));
    assert(amount <= refundable_pida_amount);

    let acp_amount = (amount * price) / pow(10, 18u8);
    abi(ACP, acp_id).withdraw(from, acp_amount);
    abi(PremiumPool, premium_pool_id).withdraw(amount, pida_contract, recipient);
    
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
    assert(acp_addr != Identity::ContractId(ContractId::from(ZERO_B256)));
    storage.acp = as_contract_id(acp_addr).unwrap();

    // set pida
    let (_, pida_addr) = reg.try_get("pida                ");
    assert(pida_addr != Identity::ContractId(ContractId::from(ZERO_B256)));
    storage.pida = as_contract_id(pida_addr).unwrap();

    let (_, premium_pool_addr) = reg.try_get("premiumPool         ");
    assert(premium_pool_addr != Identity::ContractId(ContractId::from(ZERO_B256)));
    storage.premium_pool = as_contract_id(premium_pool_addr).unwrap();

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

#[storage(read)]
fn product_is_active_internal(product: ContractId) -> bool {
    if (storage.products.get(product).is_none()) {
        return false;
    } else {
        return true;
    }
}

impl CoverPaymentManager for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;
        set_registry_internal(registry);
    }

    /***************************************
    DEPOSIT FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn deposit_stable_from(
        token: ContractId,
        from: Identity,
        recipient: Identity,
        amount: u64,
    ) {
        reentrancy_guard();
        while_unpaused();

        let sender = msg_sender().unwrap();
        assert(product_is_active_internal(as_contract_id(sender).unwrap()));

        deposit_stable_internal(token, from, recipient, amount);
    }

    #[storage(read)]
    fn deposit_stable(
        token: ContractId,
        recipient: Identity,
        amount: u64,
    ) {
        reentrancy_guard();
        while_unpaused();

        let sender = msg_sender().unwrap();

        deposit_stable_internal(token, sender, recipient, amount);
    }

    #[storage(read)]
    fn deposit_non_stable_from(
        token: ContractId,
        from: Identity,
        recipient: Identity,
        amount: u64,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) {
        reentrancy_guard();
        while_unpaused();

        let sender = msg_sender().unwrap();
        assert(product_is_active_internal(as_contract_id(sender).unwrap()));

        deposit_non_stable_internal(token, from, recipient, amount, price, price_deadline, signature);
    }

    #[storage(read)]
    fn deposit_non_stable(
        token: ContractId,
        recipient: Identity,
        amount: u64,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) {
        reentrancy_guard();
        while_unpaused();

        let sender = msg_sender().unwrap();

        deposit_non_stable_internal(token, sender, recipient, amount, price, price_deadline, signature);
    }

    /***************************************
    WITHDRAW FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn withdraw_from(
        from: Identity,
        amount: u64,
        recipient: Identity,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) {
        reentrancy_guard();

        let sender = msg_sender().unwrap();
        assert(product_is_active_internal(as_contract_id(sender).unwrap()));

        withdraw_internal(from, amount, recipient, price, price_deadline, signature);
    }

    #[storage(read)]
    fn withdraw(
        amount: u64,
        recipient: Identity,
        price: u64,
        price_deadline: u64,
        signature: B512,
    ) {
        reentrancy_guard();

        let sender = msg_sender().unwrap();

        withdraw_internal(sender, amount, recipient, price, price_deadline, signature);
    }

    #[storage(read)]
    fn charge_premiums(accounts: Vec<Identity>, premiums: Vec<u64>) {
        while_unpaused();

        let sender = msg_sender().unwrap();
        let owner_store = storage.owner;
        let acp_id = storage.acp.value;
        let is_active = product_is_active_internal(as_contract_id(sender).unwrap());

        assert(sender == abi(Registry, storage.registry.value).get("premiumCollector    ") ||
            as_address(sender).unwrap() == owner_store ||
            is_active,
        );

        assert(accounts.len() == premiums.len());
        
        abi(ACP, acp_id).burn_multiple(accounts, premiums);
    }

    /***************************************
    PRODUCT VIEW FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn get_acp_balance(account: Identity) -> u64 {
        let result = abi(ACP, storage.acp.value).balance_of(account);
        return result;
    }

    #[storage(read)]
    fn get_token_info(index: u64) -> (ContractId, bool, bool, bool, bool) {
        let token = storage.index_to_token.get(index).unwrap();
        let ti = storage.token_info.get(token).unwrap();
        return (ti.token, ti.accepted, ti.permittable, ti.refundable, ti.stable);
    }

    #[storage(read)]
    fn product_is_active(product: ContractId) -> bool {
        return product_is_active_internal(product);
    }

    #[storage(read)]
    fn num_products() -> u64 {
        return storage.products_vec.len();
    }

    #[storage(read)]
    fn get_product(product_num: u64) -> ContractId {
        return storage.products_vec.get(product_num).unwrap();
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    #[storage(write)]
    fn set_registry(registry: ContractId) {
        set_registry_internal(registry);
    }

    #[storage(read, write)]
    fn set_token_info(tokens: Vec<TokenInfo>) {
        validate_owner();
        let mut i = 0;
        while (i < tokens.len()) {
            let token = tokens.get(i).unwrap().token;
            assert(token != ContractId::from(ZERO_B256));

            // new token
            if (storage.token_info.get(token).unwrap().token == ContractId::from(ZERO_B256)) {
                storage.index_to_token.insert((storage.tokens_length + 1), token);
            };

            storage.token_info.insert(token, tokens.get(i).unwrap());

            log(
                TokenInfoSet {
                    token: tokens.get(i).unwrap().token, 
                    accepted: tokens.get(i).unwrap().accepted, 
                    permittable: tokens.get(i).unwrap().permittable, 
                    refundable: tokens.get(i).unwrap().refundable, 
                    stable: tokens.get(i).unwrap().stable,
                }
            );

            i = i + 1;
        }
    }

    #[storage(read, write)]
    fn set_paused(paused: bool) {
        validate_owner();
        let mut pause_store = storage.paused;
        pause_store = paused;
        storage.paused = pause_store;

        log(
            PauseSet {
                paused: paused,
            }
        );
    }

    #[storage(read, write)]
    fn add_product(product: ContractId) {
        validate_owner();
        assert(product != ContractId::from(ZERO_B256));
        storage.products_vec.push(product);
        let prod_len = storage.products_length;
        storage.products.insert(product, prod_len);
        storage.products_length += 1;

        log(
            ProductAdded {
                product: product,
            }
        );
    }

    #[storage(read, write)]
    fn remove_product(product: ContractId) {
        validate_owner();
        let prod_len = storage.products_length;
        let _ = storage.products_vec.remove(prod_len);
        let _ = storage.products.remove(product);
        storage.products_length -= 1;
        
        log(
            ProductRemoved {
                product: product,
            }
        );
    }
}
