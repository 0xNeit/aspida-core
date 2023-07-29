library;

use std::b512::B512;

abi Executor {
    #[storage(read, write)]
    fn inititalize(owner: Address);

    #[storage(read)]
    fn num_executors() -> u64;

    #[storage(read)]
    fn get_executor(index: u64) -> Address;

    #[storage(read)]
    fn is_executor(executor: Address) -> bool;

    #[storage(read)]
    fn verify_price(token: ContractId, price: u64, deadline: u64, signature: B512) -> bool;

    #[storage(read)]
    fn verify_premium(premium: u64, policy_holder: Address, deadline: u64, signature: B512) -> bool;

    #[storage(read, write)]
    fn add_executor(executor: Address);

    #[storage(read, write)]
    fn remove_executor(index: u64) -> Address;
}