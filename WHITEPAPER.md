
---

# DROP Protocol Whitepaper

### Trustless, Universal Storage Settlement (Mainnet-Ready)

## Abstract

DROP Protocol is a minimal, production-ready settlement layer for decentralized storage systems.

It defines a deterministic on-chain state machine for **storage responsibility transitions**.  
The protocol records only:

- when an object or container enters storage
- when an object or container exits storage

All pricing, coordination, custody rules, ownership semantics, routing, and business logic are handled **off-chain** by independent platforms.

DROP is not a storage service.  
It is neutral settlement infrastructure.

---

## 1. Introduction

Physical storage is a foundational component of logistics, supply chains, and commerce, yet it is almost always coordinated through centralized systems.

These systems typically combine:

- custody records
- pricing models
- access control
- settlement
- inventory reconciliation

This coupling creates opacity, lock-in, and high coordination overhead.

DROP Protocol addresses this by focusing **exclusively on the settlement rail** for storage events:

- Who was responsible for holding something?
- For how long?
- Under what finalized conditions is settlement allowed?

All other concerns are explicitly out of scope.

The protocol encodes only a small, auditable state machine and optional escrow settlement logic.

---

## 2. Design Goals

DROP is designed to be:

* **Minimal**: One narrowly scoped settlement layer.
* **Neutral**: Not a platform, marketplace, or operator.
* **Payment-medium agnostic**: Supports on-chain escrow or off-chain settlement.
* **Composable**: Designed to interoperate with other protocols without coupling.
* **Final**: No upgrade path or governance extensions.
* **Legible**: Deterministic state and events suitable for indexing and auditing.
* **Low-liability**: Avoids encoding custody, ownership, or regulatory logic.

Any off-chain workflows described in this document are illustrative only and are **not required, enforced, or validated** by DROP Protocol.

---

## 3. System Overview

The canonical DROP Protocol deployment consists of two contracts:

1. **DROPSpaceRegistry**
2. **DROPCore**

An optional reusable **Escrow** contract may be used for on-chain settlement.

The protocol is chain-agnostic across EVM networks and is implemented using Solidity 0.8.24.

### 3.1 Canonical Deployment

DROP Protocol is intended for Ethereum mainnet deployment.

The canonical deployment is immutable and permissionless.  
No upgrades or governance actions are possible after deployment.

---

## 4. Core Components

### 4.1 DROPSpaceRegistry: Storage Availability Declaration

`DROPSpaceRegistry` is a declarative on-chain registry of storage spaces.

Each registered space includes:

- operator address
- coarse location commitment
- total capacity and available capacity
- optional availability window
- hash commitment to off-chain terms

The registry does not include:

- pricing
- ranking
- matching
- access control
- inventory logic

Its sole purpose is to advertise availability and track capacity reservations initiated by `DROPCore`.

---

### 4.2 DROPCore: Storage State Machine and Settlement

`DROPCore` is the settlement engine.

Each storage session is represented as an ERC-721 token and follows a simple lifecycle:

```

Created -> Dropped -> Picked -> Finalized

```

Each session records:

- `storageId`
- `spaceId`
- lifecycle state
- timestamps for each transition
- optional evidence hashes
- optional escrow parameters

The protocol does not assume anything about the object being stored.

---

### 4.3 Escrow: Optional Value Settlement

DROP supports optional on-chain escrow for ETH and ERC-20 tokens.

Escrow behavior:

- funds are locked at session creation
- funds are released or refunded at finalization
- protocol fee is applied only when escrow is used

Off-chain settlement using any payment medium is fully supported.  
In that case, the protocol records state only.

---

## 5. Storage Session Lifecycle

### 5.1 Creation

A platform creates a storage session by minting a storage NFT and specifying:

- `spaceId`
- optional picker address
- optional escrow token and amount
- optional off-chain settlement reference hash

If escrow is used, funds are locked at this stage.

State: **Created**

---

### 5.2 Drop

A participant records that the object has entered storage.

- capacity is reserved in `DROPSpaceRegistry`
- timestamp and optional evidence hashes are recorded

State: **Dropped**

---

### 5.3 Pick

A participant records that the object has exited storage.

- capacity is released in `DROPSpaceRegistry`
- timestamp and optional evidence hashes are recorded

State: **Picked**

---

### 5.4 Finalization

After pick, anyone may call `finalize(storageId)`.

If escrow was used:

- funds are released to the storage operator
- immutable protocol fee is paid to the protocol treasury
- optional finalizer tip is paid

If escrow was not used:

- state is finalized without settlement

State: **Finalized**

---

## 6. Fees and Economics

### 6.1 Protocol Fee

When escrow is used, DROP enforces a fixed protocol fee:

- 0.5% of the escrowed amount
- immutable
- routed to the protocol treasury
- collected at finalize time

No protocol fee is collected for off-chain settlements.

### 6.2 Platform Economics

DROP does not encode:

- pricing
- billing duration
- penalties
- incentives

All economic policies are platform-defined and off-chain.

---

## 7. Security Model

Key security properties:

- no upgradeability
- no governance hooks
- minimal trusted surface
- escrow callable only by `DROPCore`
- deterministic lifecycle and settlement
- permissionless finalization

The `owner` role should be held by:

- a multisig
- a Safe
- or be fully renounced

---

## 8. What DROP Is and Is Not

### 8.1 DROP Is

- a storage settlement rail
- an auditable on-chain state machine
- neutral infrastructure

### 8.2 DROP Is Not

- a storage provider
- a warehouse operator
- a marketplace
- a custody system
- an inventory tracker
- a compliance framework

---

## 9. Legal Position and Responsibility Boundary

DROP is open-source software deployed on public blockchains.

The authors:

- do not operate storage facilities
- do not control stored items
- do not enforce custody rules
- do not intermediate payments
- do not collect personal data
- do not provide regulatory compliance

All responsibility rests with:

- contract deployers
- platform operators
- storage operators
- users

This is analogous to general-purpose infrastructure such as blockchain nodes or peer-to-peer networking software.

---

## 10. Conclusion

DROP Protocol is a canonical, minimal implementation of a **trustless storage settlement rail**.

It deliberately avoids modeling ownership, custody, pricing, or coordination.

By remaining narrow, deterministic, and final, DROP provides stable infrastructure that others may build on without permission or coordination.

DROP is finished infrastructure.

---

