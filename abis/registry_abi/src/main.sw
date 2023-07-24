library;

abi Registry {
    #[storage(read, write)]
    fn initialize(owner: Address);

    #[storage(read)]
    fn get(key: str[20]) -> Identity;

    #[storage(read)]
    fn try_get(key: str[20]) -> (bool, Identity);

    #[storage(read)]
    fn get_key(index: u64) -> str[20];

    #[storage(read, write)]
    fn set(keys: Vec<str[20]>, values: Vec<Identity>);
}
