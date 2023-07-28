library;

use std::b512::B512;

abi CoverPaymentManager {
    #[storage(read, write)]
    fn initialize(owner: Address, registry: ContractId);

    #[storage(read)]
    fn deposit_stable_from(
        token: ContractId,
        from: Identity,
        recipient: Identity,
        amount: u64,
    );

    #[storage(read)]
    fn deposit_stable(
        token: ContractId,
        recipient: Identity,
        amount: u64,
    );

    #[storage(read)]
    fn deposit_non_stable_from(
        token: ContractId,
        from: Identity,
        recipient: Identity,
        amount: u64,
        price: u64,
        price_deadline: u64,
        signature: B512,
    );

    #[storage(read)]
    fn deposit_non_stable(
        token: ContractId,
        recipient: Identity,
        amount: u64,
        price: u64,
        price_deadline: u64,
        signature: B512,
    );

    #[storage(read)]
    fn withdraw_from(
        from: Identity,
        amount: u64,
        recipient: Identity,
        price: u64,
        price_deadline: u64,
        signature: B512,
    );

    #[storage(read)]
    fn withdraw(
        amount: u64,
        recipient: Identity,
        price: u64,
        price_deadline: u64,
        signature: B512,
    );

    #[storage(read)]
    fn charge_premiums(accounts: Vec<Identity>, premiums: Vec<u64>);

    #[storage(read)]
    fn get_acp_balance(account: Identity) -> u64;

    #[storage(read)]
    fn get_token_info(index: u64) -> (ContractId, bool, bool, bool, bool);

    #[storage(read)]
    fn product_is_active(product: ContractId) -> bool;

    #[storage(read)]
    fn num_products() -> u64;

    #[storage(read)]
    fn get_product(product_num: u64) -> ContractId;

    #[storage(write)]
    fn set_registry(registry: ContractId);

    #[storage(read, write)]
    fn set_token_info(tokens: Vec<TokenInfo>);

    #[storage(read, write)]
    fn set_paused(paused: bool);

    #[storage(read, write)]
    fn add_product(product: ContractId);

    #[storage(read, write)]
    fn remove_product(product: ContractId);
}


pub struct TokenInfo {
    token: ContractId,
    accepted: bool,
    permittable: bool,
    refundable: bool,
    stable: bool,
}