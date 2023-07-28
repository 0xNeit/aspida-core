contract;

mod events;
mod structs;

use std::storage::*;
use std::constants::ZERO_B256;
use std::address::*;
use std::contract_id::*;
use std::auth::*;
use std::block::*;
use std::token::*;

use events::*;

use structs::*;
use bond_registry_abi::BondsRegistry;
use bond_teller_abi::*;
use locker_abi::Locker;

use reentrancy::*;

use nft::{
    approved,
    is_approved_for_all,
    mint,
    owner_of,
    tokens_minted,
};

use nft::extensions::burnable::*;

use nft::extensions::token_metadata::*;

pub enum State {
    Initialized: (),
    Uninitialized: (),
}

impl core::ops::Eq for State {
    fn eq(self, other: Self) -> bool {
        match (self, other) {
            (State::Initialized, State::Initialized) => true,
            (State::Uninitialized, State::Uninitialized) => true,
            _ => false,
        }
    }
}

storage {
    state: State = State::Uninitialized,
    owner: Address = Address {
        value: ZERO_B256,
    },
    capacity: u64 = 0,                          // capacity remaining for all bonds
    next_price: u64 = 0,                        // the price of the next bond before decay
    minimum_price: u64 = 0,                     // price floor measured in principal per 1 pida
    price_adj_num: u64 = 0,                     // factor that increases price after purchase
    price_adj_denom: u64 = 0,                   // factor that increases price after purchase
    half_life: u64 = 0,                         // factor for price decay
    last_price_update: u64 = 0,                 // last timestamp price was updated
    max_payout: u64 = 0,                        // max payout in a single bond measured in principal
    protocol_fee_bps: u64 = 0,                  // portion of principal that is sent to the dao, the rest to the pool
    terms_set: bool = false,                    // have terms been set
    capacity_is_payout: bool = false,           // capacity limit is for payout vs principal
    paused: bool = false,                       // pauses deposits
    start_time: u64 = 0,                        // timestamp bonds start
    end_time: u64 = 0,                          // timestamp bonds no longer offered
    global_vesting_term: u64 = 0,               // duration in seconds (fixed-term)

    // bonds
    num_bonds: u64 = 0,                         // total number of bonds that have been created

    bonds: StorageMap<u64, Bond> = StorageMap{},        // mapping of bondID to Bond object

    // addresses and contracts
    pida: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // pida native token
    xp_locker: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // xpLocker staking contract
    principal: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // token to accept as payment 
    underwriting_pool: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // the underwriting pool to back risks
    dao: Address = Address {
        value: ZERO_B256,
    },                                          // the dao
    bond_registry: ContractId = ContractId {
        value: ZERO_B256,
    },                                          // the bond registry
}

const MAX_BPS: u64 = 10000; // 10k basis points (100%)

/***************************************
    HELPER FUNCTIONS
***************************************/

#[storage(read)]
fn bond_price_internal() -> u64 {
    let time_since_last = timestamp() - storage.last_price_update;
    let mut price = exponential_decay(storage.next_price, time_since_last);
    if (price < storage.minimum_price) {
        price = storage.minimum_price;
    };

    price
}

#[storage(read)]
fn calculate_amount_out_internal(amount_in: u64, _stake: bool) -> u64 {
    assert(storage.terms_set);
    // exchange rate
    let bond_price = bond_price_internal();
    assert(bond_price > 0);
    let amount_out = 1000000000 * amount_in / bond_price; //
    // ensure there is remaining capacity for bond
    if (storage.capacity_is_payout) {
        // capacity in payout terms
        assert(storage.capacity >= amount_out);
    } else {
        // capacity in principal terms
        assert(storage.capacity >= amount_in);
    }
    assert(amount_out <= storage.max_payout);

    amount_out
}

#[storage(read)]
fn calculate_amount_in_internal(amount_out: u64, _stake: bool) -> u64 {
    assert(storage.terms_set);
    // exchange rate
    let bond_price = bond_price_internal();
    assert(bond_price > 0);
    let amount_in = amount_out * bond_price / 1000000000;
    // ensure there is remaining capacity for bond
    if (storage.capacity_is_payout) {
        // capacity in payout terms
        assert(storage.capacity >= amount_out);
    } else {
        // capacity in principal terms
        assert(storage.capacity >= amount_in);
    }
    assert(amount_out <= storage.max_payout);
        
    amount_in
}

#[storage(read, write)]
fn _deposit(
    amount: u64,
    min_amount_out: u64,
    depositor: Identity,
    stake: bool,
) -> (u64, u64, u64) {
    assert(!storage.paused);
    assert(storage.terms_set);
    assert(timestamp() >= storage.start_time);
    assert(timestamp() <= storage.end_time);

    let mut token_id = 0;

    let payout = calculate_total_payout(amount);

    // ensure there is remaining capacity for bond
    if (storage.capacity_is_payout) {
        // capacity in payout terms
        let cap = storage.capacity;
        assert(cap >= payout);
        storage.capacity = cap - payout;
    } else {
        // capacity in principal terms
        let cap = storage.capacity;
        assert(cap >= amount);
        storage.capacity = cap - amount;
    }

    assert(payout <= storage.max_payout);
    assert(min_amount_out <= payout);

    let protocol_fee = amount * storage.protocol_fee_bps / MAX_BPS;

    let gvt = storage.global_vesting_term;
    let xlv = storage.xp_locker.value;
    let nb = storage.num_bonds;

    // route pida
    let registry_abi = abi(BondsRegistry, storage.bond_registry.value);

    // optionally stake
    if(stake) {
        let locker_abi = abi(Locker, xlv);
        token_id = locker_abi.create_lock(depositor, payout, (timestamp() + gvt));
    } else {
        // record bond info
        token_id = nb + 1;
        let vesting_start = timestamp();
        let vesting_term = gvt;

        let new_bond = Bond {
            payout_amount: payout,
            payout_already_claimed: 0,
            principal_paid: amount,
            vesting_start: vesting_start,
            local_vesting_term: vesting_term
        };

        storage.bonds.insert(token_id, new_bond);
        mint(1, depositor);

        // let mut token_id = tokens_minted() - amount;
        set_token_metadata(Option::Some(BondMeta::new()), token_id);
        registry_abi.pull_pida(payout);

        log (
            CreateBond {
                lock_id: token_id,
                principal_amount: amount,
                payout_amount: payout, 
                vesting_start: vesting_start,
                vesting_time: vesting_term
            }
        )
    }

    (payout, token_id, protocol_fee)
}

#[storage(read, write)]
fn calculate_total_payout(deposit_amount: u64) -> u64 {
    // calculate this price
    let time_since_last = timestamp() - storage.last_price_update;
    let mut price = exponential_decay(storage.next_price, time_since_last);
    if (price < storage.minimum_price) {
        price = storage.minimum_price;
    };

    assert(price != 0);
    storage.last_price_update = timestamp();
    // calculate amount out
    let amount_out = (1000000000 * deposit_amount) / price; 
    // update next price
    storage.next_price = price + ((amount_out * (storage.price_adj_num)) / (storage.price_adj_denom));
    amount_out
}

#[storage(read)]
fn calculate_eligible_payout(bond_id: u64) -> u64 {
    let bond = storage.bonds.get(bond_id).unwrap();
    let mut eligible_payout = 0;

    // Sanity check
    assert(bond.payout_already_claimed <= bond.payout_amount);

    // Calculation if still vesting
    if (timestamp() <= bond.vesting_start + bond.local_vesting_term) {
        eligible_payout = ((bond.payout_amount * (timestamp() - bond.vesting_start)) / bond.local_vesting_term) - bond.payout_already_claimed;
    } else {
        // Calculation if vesting completed
        eligible_payout = bond.payout_amount - bond.payout_already_claimed;
    }
    eligible_payout   
}

#[storage(read)]
fn exponential_decay(init_value: u64, time: u64) -> u64 {
    let mut end_value = init_value >> (time / storage.half_life);
    end_value -= end_value * (time % storage.half_life) / storage.half_life / 2;
    end_value
}

#[storage(read, write)]
fn set_addresses_internal(
    pida: ContractId,
    xp_locker: ContractId,
    pool: ContractId,
    dao: Address,
    principal: ContractId,
    bond_registry: ContractId
) {
    assert(pida != ContractId::from(ZERO_B256));
    assert(xp_locker != ContractId::from(ZERO_B256));
    assert(pool != ContractId::from(ZERO_B256));
    assert(dao != Address::from(ZERO_B256));
    assert(principal != ContractId::from(ZERO_B256));
    assert(bond_registry != ContractId::from(ZERO_B256));

    // write pida contract to storage (read first -> update in function -> update in storage)
    let mut pida_store = storage.pida;
    pida_store = pida;
    storage.pida = pida_store;

    // write xp_locker contract to storage (read first -> update in function -> update in storage)
    let mut xp_locker_store = storage.xp_locker;
    xp_locker_store = xp_locker;
    storage.xp_locker = xp_locker_store;

    // write underwriting_pool to storage (read first -> update in function -> update in storage)
    let mut pool_store = storage.underwriting_pool;
    pool_store = pool;
    storage.underwriting_pool = pool_store;

    // write dao to storage (read first -> update in function -> update in storage)
    let mut dao_store = storage.dao;
    dao_store = dao;
    storage.dao = dao_store;

    // write principal to storage (read first -> update in function -> update in storage)
    let mut principal_store = storage.principal;
    principal_store = principal;
    storage.principal = principal_store;

    // write underwriting_pool to storage (read first -> update in function -> update in storage)
    let mut bond_registry_store = storage.bond_registry;
    bond_registry_store = bond_registry;
    storage.bond_registry = bond_registry_store;
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

#[storage(read)]
fn exists(token_id: u64) -> bool {
    let owner = owner_of(token_id);
    let mut state = false;
    if (owner.is_none()) {
        state = false;
    } else {
        state = true;
    }
    state
}


#[storage(read)]
fn is_approved_or_owner(spender: Identity, token_id: u64) -> bool {
    let owner = owner_of(token_id).unwrap();
    (spender == owner || is_approved_for_all(spender, owner) || approved(token_id).unwrap() == spender)
}

#[storage(read)]
fn token_exists(token_id: u64) {
    assert(exists(token_id) == true);
}


impl BondTeller for Contract {
    #[storage(read, write)]
    fn initialize(
        owner: Address,
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: Address,
        principal: ContractId,
        bond_registry: ContractId,
    ) {
        assert(storage.state == State::Uninitialized);
        set_addresses_internal(pida, xp_locker, pool, dao, principal, bond_registry);
        storage.state = State::Initialized;
        storage.owner = owner;
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    #[storage(read)]
    fn bond_price() -> u64 {
        return bond_price_internal();
    }

    #[storage(read)]
    fn calculate_amount_out(amount_in: u64, _stake: bool) -> u64 {
        return calculate_amount_out_internal(amount_in, _stake);
    }

    #[storage(read)]
    fn calculate_amount_in(amount_out: u64, _stake: bool) -> u64 {
        return calculate_amount_in_internal(amount_out, _stake);
    }

    /***************************************
    BONDER FUNCTIONS
    ***************************************/

    #[storage(read, write)]
    fn deposit(
        amount: u64,
        min_amount_out: u64,
        depositor: Identity,
        stake: bool
    ) -> (u64, u64) {
        let principal_id = ContractId::from(get::<b256>(storage.principal.value).unwrap());
        let dao_address = storage.dao;
        let pool = Identity::ContractId(storage.underwriting_pool);
        // accounting
        let (payout, token_id, protocol_fee) = _deposit(
            amount, 
            min_amount_out, 
            depositor, 
            stake
        );
        // route principal - put last as Checks-Effects-Interactions
        if (protocol_fee > 0) {
            transfer_to_address(
                protocol_fee,
                principal_id,
                dao_address
            );
        };

        let actual_amount = amount - protocol_fee;

        transfer(
            actual_amount,
            principal_id,
            pool
        );

        (payout, token_id)
    }

    #[storage(read, write)]
    fn claim_payout(bond_id: u64) {
        token_exists(bond_id);
        // checks
        let sender = msg_sender().unwrap();
        assert(is_approved_or_owner(sender, bond_id));

        // Payout as per vesting terms
        let mut bond = storage.bonds.get(bond_id).unwrap();
        let eligible_payout = calculate_eligible_payout(bond_id);

        bond.payout_already_claimed += eligible_payout;
        let deleted_meta: Option<BondMeta> = Option::None;

        // Burn bond if vesting completed
        if (timestamp() > bond.vesting_start + bond.local_vesting_term) {
            burn(bond_id);
            set_token_metadata(deleted_meta, bond_id);
            let _ = storage.bonds.remove(bond_id);
        }
        log(
            RedeemBond{
                bond_id: bond_id, 
                recipient: sender, 
                payout_amount: eligible_payout
            }
        );

        let pida_id = ContractId::from(get::<b256>(storage.pida.value).unwrap());

        // Place token tranasfer last as per Checks-Effects-Interactions
        transfer(eligible_payout, pida_id, sender);
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    #[storage(read, write)]
    fn pause() {
        validate_owner();
        let mut paused_state = storage.paused;
        paused_state = true;
        storage.paused = paused_state;
        log(
            Paused {}
        );
    }

    #[storage(read, write)]
    fn unpause() {
        validate_owner();
        let mut paused_state = storage.paused;
        paused_state = false;
        storage.paused = paused_state;
        log(
            Unpaused {}
        );
    }

    #[storage(write)]
    fn set_terms(terms: Terms) {
        assert(terms.start_price > 0);
        storage.next_price = terms.start_price;
        storage.minimum_price = terms.minimum_price;
        storage.max_payout = terms.max_payout;

        assert(terms.price_adj_denom != 0);
        storage.price_adj_num = terms.price_adj_num;
        storage.price_adj_denom = terms.price_adj_denom;
        storage.capacity = terms.capacity;
        storage.capacity_is_payout = terms.capacity_is_payout;

        assert(terms.start_time <= terms.end_time);
        storage.start_time = terms.start_time;
        storage.end_time = terms.end_time;
        storage.global_vesting_term = terms.global_vesting_term;

        assert(terms.half_life > 0);
        storage.half_life = terms.half_life;
        storage.terms_set = true;
        storage.last_price_update = timestamp();

        log (
            TermsSet {}
        );
    }

    #[storage(read, write)]
    fn set_fees(protocol_fee: u64) {
        validate_owner();
        assert(protocol_fee <= MAX_BPS);
        storage.protocol_fee_bps = protocol_fee;

        log(
            FeesSet {}
        );
    }

    #[storage(read, write)]
    fn set_addresses(
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: Address,
        principal: ContractId,
        bond_registry: ContractId
    ) {
        set_addresses_internal(pida, xp_locker, pool, dao, principal, bond_registry);
        log(
            AddressesSet {}
        );
    }
}
