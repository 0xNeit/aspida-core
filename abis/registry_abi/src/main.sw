library;

abi Registry {
    #[storage(read, write)]
    fn initialize(owner: Address);

    #[storage(read)]
    fn get(key: str[20]) -> ContractId;

    #[storage(read)]
    fn tryGet(key: str[20]) -> (bool, ContractId);

    #[storage(read)]
    fn getKey(index: u64) -> str[20];

    #[storage(read, write)]
    fn set(keys: Vec<str[20]>, values: Vec<ContractId>);
}
