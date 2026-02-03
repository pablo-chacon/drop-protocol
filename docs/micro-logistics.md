
---

# DeDe + DROP: Permissionless Micro-Logistics by Composition

This document describes what emerges when **DeDe Protocol** and **DROP Protocol**
are used together.

Neither protocol models a supply chain.
Neither protocol attempts to coordinate logistics.
Neither protocol is aware of the other.

The effects described here exist **only because of that separation**.

---

## Core Principle

DeDe and DROP together enable **permissionless micro-logistics**.

This works precisely because:

- DeDe models **movement responsibility**
- DROP models **storage responsibility**
- Neither protocol models ownership, inventory, routing, or coordination

The protocols never is the supply chain.

---

## 1. Fractional Logistics

Consider a concrete example.

A container with 100 iPhones arrives at a location.

On-chain reality at that moment is only:

```

DROP:
object_set stored at location L from time T₀

```

Nothing else is recorded.
No quantities.
No inventory graph.
No destinations.
No routing plan.


Anyone can **slice the work**, not the object.

Multiple independent actors can do the following:

- DeDe -> pick up a partial quantity from DROP
- DROP -> store the remainder or re-store partials
- DeDe -> deliver partials onward

Each action is independent.

This creates **logistics sharding**, not custody ambiguity.

Each shard has:

- its own DeDe segment (movement)
- its own DROP segment (rest)
- its own proof-of-service and settlement
- zero coupling to other shards

No coordinator is required.

---

## 2. Why This Does Not Break Custody or Ownership

Key insight:

**DeDe and DROP do not model ownership. They model responsibility.**

Ownership remains:

- off-chain
- platform-defined
- inferred by business logic

Even with:

- 10 carriers
- 20 DROP locations
- 100 partial movements

On-chain facts remain atomic and non-conflicting.

### DeDe facts

```

Carrier X moved quantity Q from A to B at time T

```

### DROP facts

```

Storage Y held quantity Q at location L between T₁ -> T₂

```

No protocol ever needs to know:

- total inventory
- remaining quantity
- destination graph
- routing plan
- global state

The workflow pattern is independently repeatable until the "phone" reach it's destination.

---

## 3. Capabilities, Not Platforms

Because participation is permissionless, anyone can act as:

- a last-mile carrier
- a temporary storage unit
- a relay
- a splitter
- a consolidator

This creates **emergent specialization**.

Examples:

- people with vans do last-mile DeDe hops
- shops act as micro-DROP nodes overnight
- warehouses provide long-term DROP storage
- couriers chain DeDe -> DROP -> DeDe arbitrage

None of this behavior is encoded on-chain.

The chain only records **what happened**, not **why**.

---

## 4. Why This Remains Decentralized at Scale

There is no point where the system requires:

- global routing agreement
- centralized batching
- inventory reconciliation
- coordinator authority

This is because:

- MOVE and REST are never mixed
- accountability is always local
- settlement is always final per segment

As a result, the system resists:

- protocol-level monopolies
- chokepoints
- forced aggregation

Any hub that forms is **economic**, not structural.

It can be bypassed instantly.

---

## 5. The Deeper Effect: Logistics as Fungible Labor

The deeper structural shift is:

Logistics becomes a graph of **independently settleable labor contributions**.

Participants do not “join a network”.

They simply:

- accept a DeDe hop
- accept a DROP custody window
- get paid
- exit

This mirrors what happened with:

- compute -> containers
- bandwidth -> CDNs
- payments -> settlement rails

But applied to physical reality.

---

## Summary

DeDe and DROP together do not create a supply chain.

They create a **ledger of responsibility transitions**.

Because responsibility is local, atomic, and final:

- coordination becomes optional
- specialization becomes emergent
- scale does not introduce centralization

This works because the protocols remain minimal and separate.


---

