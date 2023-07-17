library;

pub struct LockCreated {
    xp_lock_id: u64,
}

pub struct LockUpdated {
    xp_lock_id: u64, 
    amount: u64, 
    end: u64
}
    
pub struct Withdraw {
    xp_lock_id: u64, 
    amount: u64,
}

pub struct XpLockListenerAdded {
    listener: ContractId,
}

pub struct XpLockListenerRemoved {
    listener: ContractId,
}