library;

abi CoverProduct {
    #[storage(read)]
    fn min_acp_required(policy_holder: Address) -> u64;
}
