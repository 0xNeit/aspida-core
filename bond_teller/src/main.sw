contract;

mod events;
mod structs;

use std::storage::*;
use std::constants::ZERO_B256;
use std::address::*;
use std::contract_id::*;
use std::auth::{AuthError, msg_sender};
use std::block::*;

use events::*;

use structs::*;

pub enum Errors {
    AtCapacity: (),
    BondTooLarge: (),
    CannotReinitialize: (),
    Concluded: (),
    NotInitialized: (),
    NotOwner: (),
    NotStarted: (),
    InvalidAddress: (),
    InvalidPrice: (),
    InvalidDenom: (),
    InvalidDate: (),
    InvalidHalfLife: (),
    InvalidFee: (),
    InsufficientAmount: (),
    Paused: (),
    Slippage: (),
    ZeroAddress: (), 
}

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

abi BondTeller {
    #[storage(read, write)]
    fn initialize(
        owner: Address,
        pida: ContractId,
        xp_locker: ContractId,
        pool: ContractId,
        dao: Address,
        principal: ContractId,
        bond_registry: ContractId,
    );

    #[storage(read, write)]
    fn pause();

    #[storage(read, write)]
    fn unpause();

    #[storage(write)]
    fn set_terms(terms: Terms);

    #[storage(read, write)]
    fn set_fees(protocol_fee: u64);
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

/**
    * @notice Create a bond by depositing `amount` of `principal`.
    * @param amount Amount of principal to deposit.
    * @param minAmountOut The minimum PIDA out.
    * @param depositor The bond recipient, default msg.sender.
    * @param stake True to stake, false to not stake.
    * @return payout The amount of PIDA in the bond.
    * @return tokenID The ID of the newly created bond or lock.
    * @return protocolFee Amount of principal paid to dao
*/
/*fn deposit(
    amount: u64,
    min_amount_out: u64,
    depositor: Address,
    stake: bool,
) -> (u64, u64, u64) {
    require(depositor != Address::from(ZERO_B256), Errors::ZeroAddress);
    require(!storage.paused, Errors::Paused);

    require(storage.terms_set, Errors::NotInitialized);
    require(timestamp() >= storage.start_time, Errors::NotStarted);
    require(timestamp() <= storage.end_time, Errors::Concluded);

    let payout = calculate_total_payout(amount);

    // ensure there is remaining capacity for bond
    if (storage.capacity_is_payout) {
        // capacity in payout terms
        let cap = storage.capacity;
        require(cap >= payout, Errors::AtCapacity);
        storage.capacity = cap - payout;
    } else {
        // capacity in principal terms
        cap = storage.capacity;
        require(cap >= amount, Errors::AtCapacity);
        storage.capacity = cap - amount;
    }

    require(payout <= storage.max_payout, Errors::BondTooLarge);
    require(min_amount_out <= payout, Errors::Slippage);

    // route solace
    resistry_abi = abi(BondsRegistry, storage.bond_registry.value);
    registry_abi.pull_pida(payout);

    // optionally stake
    if(stake) {
        let locker_abi = abi(Locker, storage.xp_locker.value);
        let token_id = locker_abi.create_lock(depositor, payout, (timestamp() + storage.global_vesting_term))
    } else {
        // record bond info
        let token_id = storage.num_bonds + 1;
        let vesting_start = timestamp();
        let vesting_term = storage.global_vesting_term;
          bonds[tokenID] = Bond({
              payoutAmount: payout,
              payoutAlreadyClaimed: 0,
              principalPaid: amount,
              vestingStart: vestingStart,
              localVestingTerm: vestingTerm
          });
          _mint(depositor, tokenID);
          emit CreateBond(tokenID, amount, payout, vestingStart, vestingTerm);
        }

        protocolFee = amount * protocolFeeBps / MAX_BPS;
        return (payout, tokenID, protocolFee);
}*/
/**
    * @notice Sets the addresses to call out in storage.
    * Can only be called by the current Owner.
    * @param pida The PIDA token ContractId.
    * @param xp_locker The xpLocker ContractId.
    * @param pool The underwriting pool.
    * @param dao The DAO wallet.
    * @param principal The token that users deposit.
    * @param bond_registry The bond registry.
*/
#[storage(read, write)]
fn set_addresses(
    pida: ContractId,
    xp_locker: ContractId,
    pool: ContractId,
    dao: Address,
    principal: ContractId,
    bond_registry: ContractId
) {
    require(pida != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(xp_locker != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(pool != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(dao != Address::from(ZERO_B256) , Errors::ZeroAddress);
    require(principal != ContractId::from(ZERO_B256), Errors::ZeroAddress);
    require(bond_registry != ContractId::from(ZERO_B256), Errors::ZeroAddress);

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
    require(storage.owner == sender, Errors::NotOwner);
}

/**
    * @notice Calculate the payout in PIDA and update the current price of a bond.
    * @param depositAmount The amount of `principal` to deposit.
    * @return amountOut The amount of PIDA out.
*/
#[storage(read)]
fn calculate_total_payout(deposit_amount: u64) -> u64 {
    // calculate this price
    let time_since_last = timestamp() - storage.last_price_update;
    let mut price = exponential_decay(storage.next_price, time_since_last);
    if (price < storage.minimum_price) {
        price = storage.minimum_price;
    };

    require(price != 0, Errors::InvalidPrice);
    storage.last_price_update = timestamp();
    // calculate amount out
    let amount_out = (1000000000 * deposit_amount) / price; 
    // update next price
    storage.next_price = price + ((amount_out * (storage.price_adj_num)) / (storage.price_adj_denom));
    amount_out
}

/**
    * @notice Calculates current eligible payout on a bond, based on `bond.local_vestingTerm` and `bond.payout_already_claimed`.
    * @param bondID The ID of the bond to calculate eligible payout on.
    * @return eligiblePayout Amount of PIDA that can be currently claimed for the bond.
*/
#[storage(read)]
fn calculate_eligible_payout(bond_id: u64) -> u64 {
    let bond = storage.bonds.get(bond_id).unwrap();
    let mut eligible_payout = 0;

    // Sanity check
    require(bond.payout_already_claimed <= bond.payout_amount, Errors::InsufficientAmount);

    // Calculation if still vesting
    if (timestamp() <= bond.vesting_start + bond.local_vesting_term) {
        eligible_payout = ((bond.payout_amount * (timestamp() - bond.vesting_start)) / bond.local_vesting_term) - bond.payout_already_claimed;
    } else {
        // Calculation if vesting completed
        eligible_payout = bond.payout_amount - bond.payout_already_claimed;
    }
    eligible_payout   
}

/**
    * @notice Calculates exponential decay.
    * @dev Linear approximation, trades precision for speed.
    * @param init_value The initial value.
    * @param time The time elapsed.
    * @return end_value The value at the end.
*/
#[storage(read)]
fn exponential_decay(init_value: u64, time: u64) -> u64 {
    let mut end_value = init_value >> (time / storage.half_life);
    end_value -= end_value * (time % storage.half_life) / storage.half_life / 2;
    end_value
}


impl BondTeller for Contract {
    /**
     * @notice Initializes the teller.
     * @param owner The address of the owner.
     * @param pida The PIDA token.
     * @param xp_locker The xpLocker contract.
     * @param pool The underwriting pool.
     * @param dao The DAO.
     * @param principal The token that users deposit.
     * @param bond_registry The bond depository.
    */
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
        require(storage.state == State::Uninitialized, Errors::CannotReinitialize);
        set_addresses(pida, xp_locker, pool, dao, principal, bond_registry);
        storage.state = State::Initialized;
        storage.owner = owner;
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Pauses deposits.
     * Can only be called by the current owner.
    */
    #[storage(read, write)]
    fn pause() {
        validate_owner();
        storage.paused = true;
        log (
            Paused {}
        );
    }

    /**
     * @notice Unpauses deposits.
     * Can only be called by the current owner.
    */
    #[storage(read, write)]
    fn unpause() {
        validate_owner();
        storage.paused = false;
        log(
            Unpaused {}
        );
    }

    /**
     * @notice Sets the bond terms.
     * Can only be called by the current owner.
     * @param terms The terms of the bond.
    */
    #[storage(write)]
    fn set_terms(terms: Terms) {
        require(terms.start_price > 0, Errors::InvalidPrice);
        storage.next_price = terms.start_price;
        storage.minimum_price = terms.minimum_price;
        storage.max_payout = terms.max_payout;

        require(terms.price_adj_denom != 0, Errors::InvalidDenom);
        storage.price_adj_num = terms.price_adj_num;
        storage.price_adj_denom = terms.price_adj_denom;
        storage.capacity = terms.capacity;
        storage.capacity_is_payout = terms.capacity_is_payout;

        require(terms.start_time <= terms.end_time, Errors::InvalidDate);
        storage.start_time = terms.start_time;
        storage.end_time = terms.end_time;
        storage.global_vesting_term = terms.global_vesting_term;

        require(terms.half_life > 0, Errors::InvalidHalfLife);
        storage.half_life = terms.half_life;
        storage.terms_set = true;
        storage.last_price_update = timestamp();

        log (
            TermsSet {}
        );
    }

    /**
     * @notice Sets the bond fees.
     * @param protocolFee The fraction of `principal` that will be sent to the dao measured in BPS.
    */
    #[storage(read, write)]
    fn set_fees(protocol_fee: u64) {
        validate_owner();
        require(protocol_fee <= MAX_BPS, Errors::InvalidFee);
        storage.protocol_fee_bps = protocol_fee;

        log(
            FeesSet {}
        );
    }
}
