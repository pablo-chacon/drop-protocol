
---

# Decentralized Storage Settlement (DROP) Protocol

**Decentralized Storage Settlement Protocol (Peer-to-Peer Storage State)**

---

## Legal Disclaimer

This repository contains general-purpose, open-source smart contracts.  
The authors and contributors:

* do not operate any storage service, warehouse, locker network, or marketplace  
* do not verify, supervise, or vet storage operators, users, or platforms  
* do not provide legal, financial, tax, or regulatory advice  
* are not responsible for deployments, integrations, or real-world usage  

All deployments of DROP Protocol are performed **at the risk of the deployer and the integrating platform**.

No warranty of any kind is provided.  
The software is offered strictly **as-is**, without guarantees of fitness for any purpose.  
The authors are not liable for any damages, losses, claims, theft, destruction, misplacement, regulatory issues, or disputes arising from the use, misuse, or failure of this software or any derivative work.

By using, deploying, integrating, or interacting with this software in any form, you agree that all responsibility for legal compliance, operation, custody, settlement, and outcomes lies solely with you.

---

## Protocol Finality & Immutability

**DROP Protocol is finished infrastructure.**

The core smart contracts are intentionally minimal, deterministic, and **will not be modified, upgraded, or extended**. There is no upgrade path, governance mechanism, or maintainer intervention.

DROP is provided as neutral, general-purpose settlement infrastructure. Its behavior is fully defined by the deployed code and does not depend on any individual, organization, or ongoing development.

All future innovation is expected to happen **off-chain or on top of the protocol**, without requiring changes to the protocol itself.

---

## **DROP Protocol: Trustless, Universal Storage Settlement (Ethereum-Mainnet)**

**DROP Protocol** is a minimal, self-contained, production-ready settlement layer for decentralized storage systems.

**Any Object or Container** -> Drop -> Storage -> Pick -> Settlement.

**DeFi/CeFi Agnostic:**  
DROP enables storage settlement for platforms, logistics systems, supply chains, and financial workflows without enforcing any payment medium.

**This repository contains only the immutable smart contracts and the deploy script.**

---

## **Ethereum Mainnet Deployment**

Official DROP Protocol contract addresses:

DROPCore:          0x924cC808389F0385dBe3F0248796147D85635338
DROPSpaceRegistry: 0xfbf7Ed40f0FA992D2Ddc07250FE2D0e72Cbd12c9
Escrow:            0x9e859D91C900F799F23F55FffCdAf389118a5766
protocolTreasury:  0xcd89321D5a9080e417ac01c8F46F643548ad7C04

---

## **Micro-Logistics example** 

Fractional Logistics conceptual workflow:

[micro-logistics.md](https://github.com/pablo-chacon/drop-protocol/blob/main/docs/micro-logisitcs.md)

---

## **Start building**

Platform scaffolding, examples, and integrations are provided separately.

**DROP Templates (platform examples, not SDKs):**  
Link will be published in `DROP-Templates` repository.

This repository intentionally contains **no SDKs, APIs, or platform helpers**.

---

## **Repo Structure**

```

.
├── contracts
│   ├── DROPCore.sol
│   ├── DROPSpaceRegistry.sol
│   └── Escrow.sol
├── foundry.lock
├── foundry.toml
├── README.md
├── script
│   └── DeployProtocol.s.sol
└── WHITEPAPER.md

```

---

## **Centralized Storage Platforms VS DROP Protocol**

| **System Function** | **Centralized Storage Providers** | **DROP Protocol** |
| ------------------- | --------------------------------- | ----------------- |
| **Custody Records** | Private databases                  | On-chain state machine |
| **Availability**   | Opaque platform listings           | Declarative on-chain registry |
| **Settlement**     | Manual or custodial                | Deterministic escrow or off-chain anchor |
| **Fees**           | Mutable and hidden                 | Immutable protocol fee |
| **Payment Medium** | Platform-restricted                | Platform-defined, protocol-agnostic |
| **Disputes**       | Platform arbitration               | Optional, explicit, final |
| **Data Ownership** | Platform-controlled                | Neutral infrastructure |

---

## **NFT as a Representation of a Physical Storage Session**

DROP uses NFTs as non-speculative infrastructure.

An NFT is a globally unique, transferable state container. Unlike fungible assets, an NFT represents exactly one indivisible storage session and binds authority to advance its lifecycle.

In DROP, the storage NFT binds together:

* **storageId**
* **spaceId**
* **lifecycleState**
* **timestamps**
* **optional escrow authority**
* **optional evidence hashes**

The protocol does not put stored items on-chain.  
The NFT anchors the storage session’s identity and lifecycle in a public, tamper-resistant state machine.

Possession of the NFT represents the authority to advance the storage lifecycle and finalize settlement. No identity continuity, account system, or trusted operator is required.

---

## **What DROP Protocol Provides**

### **1. DROPSpaceRegistry: storage availability declaration**

* On-chain registration of storage spaces  
* Capacity and availability tracking  
* Coarse location commitment  
* Hash commitment to off-chain terms  
* No pricing or ranking logic  

---

### **2. DROPCore: storage settlement engine**

* ERC-721 storage sessions  
* Drop -> pick -> finalize lifecycle  
* Optional on-chain escrow settlement  
* Immutable protocol fee (0.5%) paid to `protocolTreasury`  
* Permissionless finalization with a small finalizer tip  
* Deterministic events for indexing  

---

### **3. Escrow: optional value settlement**

* Reusable escrow contract  
* Supports ETH and ERC-20 tokens  
* Releases funds based on storage lifecycle  
* Off-chain settlement remains fully supported  

---

This repository is intentionally bare-metal.  
It contains only the canonical protocol implementation.

Platforms, UIs, APIs, storage operators, payment adapters, and integrations live in separate repositories.

---

## **Finalization and Disputes**

### **Finalization**

* After pick, anyone may call `finalize(storageId)`.
* If escrow was used:

  * `Escrow.releaseWithFees` sends funds to:
    * storage operator
    * protocol treasury
    * finalizer (tip)
* If no escrow was used:
  * Finalization records state only.
* State becomes **Finalized**.

---

### **Disputes**

* Platform may call `dispute(storageId, reasonHash)` in allowed states.
* Owner may later call `resolve(storageId, winner)`.

Depending on resolution:

* If `winner == operator`: escrow settles normally.
* Otherwise: escrow refunds the platform.

State becomes **Finalized**.

---

## **Security Model**

* Protocol fee is immutable and cannot be changed post-deploy
* No upgrade hooks
* No hidden admin controls
* `owner` should be:
  * a multisig
  * a Safe
  * or fully renounced

---

## **Philosophy**

DROP Protocol is:

* Minimal
* Neutral
* Permissionless
* Composable
* Finished

Any storage system can adopt it.
DROP does not adopt your architecture.

---

## **License**

MIT License

Copyright (c) 2025 Emil Karlsson

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

---

## **Contact**

**Contact Email:** pablo-chacon-ai@proton.me

---

