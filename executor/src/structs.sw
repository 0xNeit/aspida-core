library;

pub struct PriceData {
    token: ContractId,
    price: u64,
    deadline: u64,
}

pub struct PremiumData {
    premium: u64,
    policy_holder: Address,
    deadline: u64,
}