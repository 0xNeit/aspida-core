contract;

mod events;

use std::auth::*;
use std::constants::ZERO_B256;
use std::storage::*;
use std::token::*;
use std::call_frames::*;

use cover_product_abi::*;
use cover_points_abi::*;
use events::*;

pub struct Transfer {
    sender: Identity,
    recipient: Identity,
    amount: u64,
}

storage {
    owner: Address = Address {
        value: ZERO_B256,
    },
    balances: StorageMap<Identity, u64> = StorageMap {},
    balances_non_refundable: StorageMap<Identity, u64> = StorageMap {},
    total_supply: u64 = 0,
    name: str[19] = "Aspida Cover Points",
    symbol: str[3] = "ACP",
    decimals: u8 = 9u8,
    acp_movers: StorageMap<Identity, u64> = StorageMap {},
    acp_movers_vec: StorageVec<Identity> = StorageVec {},
    acp_retainers: StorageMap<ContractId, u64> = StorageMap {},
    acp_retainers_vec: StorageVec<ContractId> = StorageVec {},
}

fn as_address(to: Identity) -> Option<Address> {
    match to {
        Identity::Address(addr) => Option::Some(addr),
        Identity::ContractId(_) => Option::None,
    }
}

#[storage(read)]
fn balance_of_internal(account: Identity) -> u64 {
    let balance = storage.balances.get(account).unwrap();
    return balance;
}

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

fn sub_or_zero(a: u64, b: u64) -> u64 {
    if (a >= b) {
        return (a - b);
    } else {
        return 0;
    }
}

#[storage(read)]
fn is_acp_mover_internal(account: Identity) -> bool {
    if (storage.acp_movers.get(account).is_none()) {
        return false;
    } else {
        return true;
    }
}

#[storage(read)]
fn is_acp_retainer_internal(account: ContractId) -> bool {
    if (storage.acp_retainers.get(account).is_none()) {
        return false;
    } else {
        return true;
    }
}

#[storage(read, write)]
fn burn_internal(account: Identity, amount: u64) {
    let mut account_balance = storage.balances.get(account).unwrap(); // TODO check for None
    assert(account_balance >= amount);
    account_balance -= amount;
    storage.total_supply += amount;
    // burn nonrefundable amount first
    let bnr1 = storage.balances_non_refundable.get(account).unwrap();
    let bnr2 = sub_or_zero(bnr1, amount);

    if (bnr2 != bnr1) {
        storage.balances_non_refundable.insert(account, bnr2);
    }
}

#[storage(read)]
fn min_acp_required_internal(account: Address) -> u64 {
    let mut amount = 0;
    let len = storage.acp_retainers_vec.len();
    let mut i = 0;
    while (i < len) {
        let cp = abi(CoverProduct, storage.acp_retainers_vec.get(i).unwrap().value);
        amount += cp.min_acp_required(account);
        i = i + 1;
    }
    return amount;
}

impl ACP for Contract {
    #[storage(read, write)]
    fn initialize(owner: Address) {
        let mut owner_store = storage.owner;
        owner_store = owner;
        storage.owner = owner_store;
    }

    #[storage(read)]
    fn name() -> str[19] {
        let name_store = storage.name;
        return name_store;
    }

    #[storage(read)]
    fn symbol() -> str[3] {
        let symbol_store = storage.symbol;
        return symbol_store;
    }

    #[storage(read)]
    fn decimals() -> u8 {
        let decimals_store = storage.decimals;
        return decimals_store;
    }

    #[storage(read)]
    fn total_supply() -> u64 {
        let total_supply_store = storage.total_supply;
        return total_supply_store;
    }

    #[storage(read)]
    fn balance_of(account: Identity) -> u64 {
        let balance = balance_of_internal(account);
        return balance;
    }

    #[storage(read, write)]
    fn transfer(amount: u64, recipient: Identity) -> bool {
        let sender = msg_sender().unwrap();
        assert(is_acp_mover_internal(sender) == true);

        // fetch sender's balance
        let sender_balance = storage.balances.get(sender).unwrap();
        assert(sender_balance >= amount);
        // subtract amount from balance
        let new_sender_balance = sender_balance - amount;

        // update balance
        let _ = storage.balances.remove(sender);
        storage.balances.insert(sender, new_sender_balance);

        // fetch recipients balance
        let recipient_balance = storage.balances.get(recipient).unwrap();
        let new_recipient_balance = recipient_balance + amount;

        // update recipient's balance
        let _ = storage.balances.remove(recipient);
        storage.balances.insert(recipient, new_recipient_balance);

        // transfer nonrefundable amount first
        let bnr1 = storage.balances_non_refundable.get(sender).unwrap();
        let bnr2 = sub_or_zero(bnr1, amount);

        if (bnr2 != bnr1) {
            let _ = storage.balances_non_refundable.remove(sender);
            let _ = storage.balances_non_refundable.insert(sender, bnr2);

            if (storage.balances_non_refundable.get(recipient).is_none()) {
                storage.balances_non_refundable.insert(recipient, (bnr1 - bnr2));
            } else {
                // let recipient_refundable = storage.balances_non_refundable.get(recipient);
                let _ = storage.balances_non_refundable.remove(recipient);
                storage.balances_non_refundable.insert(recipient, (recipient_balance + (bnr1 - bnr2)));
            }
        };

        transfer(amount, contract_id(), recipient);

        log(Transfer {
            sender: sender,
            recipient: recipient,
            amount: amount,
        });

        return true;
    }

    #[storage(read, write)]
    fn mint(account: Identity, amount: u64, is_refundable: bool) {
        let sender = msg_sender().unwrap();
        assert(is_acp_mover_internal(sender) == true);

        let mut total_supply = storage.total_supply;
        total_supply += amount;
        storage.total_supply = total_supply;

        let mut account_balance = storage.balances.get(account).unwrap();
        account_balance += amount;
        storage.balances.insert(account, account_balance);

        if (!is_refundable) {
            // add to non-refunerable balances map as well for the same user balance tracking purpose
            let mut refundable_balance = storage.balances_non_refundable.get(account).unwrap();
            refundable_balance += amount;
            storage.balances_non_refundable.insert(account, refundable_balance);
        }

        mint(amount);
    }

    #[storage(read, write)]
    fn burn_multiple(accounts: Vec<Identity>, amounts: Vec<u64>) {
        let sender = msg_sender().unwrap();
        assert(is_acp_mover_internal(sender));
        let len = accounts.len();
        assert(len == amounts.len());

        let mut i = 0;
        while (i < len) {
            burn_internal(accounts.get(i).unwrap(), amounts.get(i).unwrap());
            i += 1;
        }
    }
    #[storage(read, write)]
    fn burn(account: Identity, amount: u64) {
        let sender = msg_sender().unwrap();
        assert(is_acp_mover_internal(sender));
        burn_internal(account, amount);
    }

    #[storage(read, write)]
    fn withdraw(account: Identity, amount: u64) {
        // checks
        let sender = msg_sender().unwrap();
        assert(is_acp_mover_internal(sender));
        let bal = storage.balances.get(account).unwrap();
        let bnr = storage.balances_non_refundable.get(account).unwrap();
        let br = sub_or_zero(bal, bnr);
        assert(br >= amount);
        let min_acp = min_acp_required(as_address(account).unwrap());
        let new_bal = bal - amount;
        assert(new_bal >= min_acp);
        // effects
        storage.total_supply -= amount;
        storage.balances.insert(account, new_bal)
    }
    

    /***************************************
    MOVER AND RETAINER FUNCTIONS
    ***************************************/
    #[storage(read)]
    fn min_acp_required(account: Address) -> u64 {
        return min_acp_required_internal(account);
    }

    #[storage(read)]
    fn is_acp_mover(account: Identity) -> bool {
        return is_acp_mover_internal(account);
    }

    #[storage(read)]
    fn acp_mover_length() -> u64 {
        return storage.acp_movers_vec.len();
    }

    #[storage(read)]
    fn acp_mover_list(index: u64) -> Identity {
        return storage.acp_movers_vec.get(index).unwrap();
    }

    #[storage(read)]
    fn is_acp_retainer(account: ContractId) -> bool {
        return is_acp_retainer_internal(account);
    }

    #[storage(read)]
    fn acp_retainer_length() -> u64 {
        return storage.acp_retainers_vec.len();
    }

    #[storage(read)]
    fn acp_retainer_list(index: u64) -> ContractId {
        return storage.acp_retainers_vec.get(index).unwrap();
    }

    #[storage(read)]
    fn balance_of_non_refundable(account: Identity) -> u64 {
        return storage.balances_non_refundable.get(account).unwrap();
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/
    #[storage(read, write)]
    fn set_acp_mover_statuses(acp_movers: Vec<Identity>, statuses: Vec<bool>) {
        validate_owner();
        let len = acp_movers.len();
        assert(statuses.len() == len);
        let mut i = 0;
        while (i < len) {
            if (statuses.get(i).unwrap()) {
                storage.acp_movers_vec.push(acp_movers.get(i).unwrap());
                storage.acp_movers.insert(acp_movers.get(i).unwrap(), i);
            } else {
                let _ = storage.acp_movers_vec.remove(i);
                let _ = storage.acp_movers.remove(acp_movers.get(i).unwrap());
            };

            log(AcpMoverStatusSet {
                acp_mover: acp_movers.get(i).unwrap(),
                status: statuses.get(i).unwrap(),
            });

            i += 1;
        };
    }

    #[storage(read, write)]
    fn set_acp_retainer_statuses(acp_retainers: Vec<ContractId>, statuses: Vec<bool>) {
        validate_owner();
        let len = acp_retainers.len();
        assert(statuses.len() == len);
        let mut i = 0;
        while (i < len) {
            if (statuses.get(i).unwrap()) {
                storage.acp_retainers_vec.push(acp_retainers.get(i).unwrap());
                storage.acp_retainers.insert(acp_retainers.get(i).unwrap(), i);
            } else {
                let _ = storage.acp_retainers_vec.remove(i);
                let _ = storage.acp_retainers.remove(acp_retainers.get(i).unwrap());
            };

            log(AcpRetainerStatusSet {
                acp_retainer: acp_retainers.get(i).unwrap(),
                status: statuses.get(i).unwrap(),
            });

            i += 1;
        }
    }
}
