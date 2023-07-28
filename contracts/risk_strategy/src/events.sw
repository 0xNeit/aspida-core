library;

/// Emitted when a product's risk parameters are set at initialization.
pub struct ProductRiskParamsSet {
    product: ContractId, 
    weight: u64, 
    price: u64, 
    divisor: u64,
}

/// Emitted when governance adds a product.
pub struct ProductAddedByGovernance {
    product: ContractId, 
    weight: u64, 
    price: u64, 
    divisor: u64,
}

/// Emitted when governance updates a product.
pub struct ProductUpdatedByGovernance {
    product: ContractId, 
    weight: u64, 
    price: u64, 
    divisor: u64,
}

/// Emitted when governance removes a product.
pub struct ProductRemovedByGovernance {
    product: ContractId,
}

/// Emitted when governance sets product risk params.
pub struct ProductRiskParamsSetByGovernance {
    product: ContractId, 
    weight: u64, 
    price: u64, 
    divisor: u64,
}

/// Emitted when RiskManager is set.
pub struct RiskManagerSet {
    risk_manager: ContractId,
}