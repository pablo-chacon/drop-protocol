// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IDROPSpaceRegistry {
    function spaces(uint256 spaceId)
        external
        view
        returns (
            address operator,
            bool active,
            bytes32 coarseLocationHash,
            bytes32 termsHash,
            uint64 availableFrom,
            uint64 availableTo,
            uint64 capacityTotal,
            uint64 capacityAvailable,
            string memory metadataCid
        );

    function getOperator(uint256 spaceId) external view returns (address);
    function reserveOne(uint256 spaceId) external;
    function releaseOne(uint256 spaceId) external;
}

interface IEscrow {
    function fund(uint256 id, address token, uint256 amount, address payer) external payable;

    function releaseWithFees(
        uint256 id,
        address operator,
        address platformFeeTo,
        uint16 platformFeeBps,
        address protocolFeeTo,
        uint16 protocolFeeBps,
        address caller,
        uint16 callerTipBps
    ) external;

    function refund(uint256 id, address to) external;
}

/// @title DROPCore
/// @notice Trustless settlement core for decentralized P2P storage.
///
/// ## Roles
///   - Dropper  : deposits an item into the storage space.
///                Creates the session and funds escrow.
///   - Operator : the registered storage provider. Trusted third party.
///                Attests drop() (item arrived) and pick() (item left).
///   - Picker   : retrieves the item. Calls confirmPickup() as Proof-of-Custody.
///                Dropper and picker MAY be the same address — protocol is neutral.
///
/// ## Settlement
///   Escrow releases to the storage operator when:
///     (a) picker calls confirmPickup(), explicit Proof-of-Custody, OR
///     (b) 48 hours elapse after pick(), permissionless timeout finalize.
///   If no escrow was used, finalize() records state only; settlement is off-chain.
///
/// ## No disputes, no arbitration, no admin intervention
///   DROP does not adjudicate disputes. That is a platform concern.
///   Economic enforcement is natural: the operator is only paid after pick() is
///   attested. If the operator behaves fraudulently, platforms handle consequences
///   off-chain. The protocol does not need to.
///   The only owner-controlled parameter is finalizeTipBps (liveness incentive,
///   capped at 1%). Owner may renounce after deploy for full immutability.
///
/// ## NFT
///   Each storage session is an ERC-721 token.
///   Non-speculative infrastructure: possession = authority to advance state.
///
/// ## Protocol fee
///   Immutable 0.5% to protocolTreasury.
///   Platform fee is always 0 at protocol level, platform economics are off-chain.
///
/// ## Philosophy
///   Minimal. Neutral. Permissionless. Finished.
///   DROP does not route, price, match, identify, or arbitrate. Platforms do that.
contract DROPCore is ERC721, Ownable2Step {

    // State machine 
    enum State {
        None,      // storageId not yet created
        Created,   // session created, item not yet in storage
        Dropped,   // operator attested item is in storage (capacity reserved)
        Picked,    // operator attested item has left storage (capacity released)
        Finalized  // settlement complete (or state-only if no escrow)
    }

    // Storage session
    struct StorageSession {
        uint256 spaceId;

        address dropper;  // created session + funded escrow
        address picker;   // expected picker (informational; not enforced on-chain)
                          // dropper == picker is valid — protocol is neutral

        State state;

        uint64 createdAt;
        uint64 droppedAt;
        uint64 pickedAt;
        uint64 finalizeAfter; // pickedAt + 48h; permissionless finalize after this

        // Evidence anchors — hashes only, content lives off-chain
        bytes32 dropEvidenceHash; // e.g. seal digest, photo digest, sensor reading
        bytes32 pickEvidenceHash;
        string  dropEvidenceCid;  // optional IPFS/Arweave CID
        string  pickEvidenceCid;

        // Optional on-chain escrow
        address escrowToken;  // address(0) = ETH
        uint256 escrowAmount; // 0 = off-chain settlement only
        bool    escrowed;

        // Optional off-chain settlement reference
        bytes32 settlementRefHash; // hash(invoice / txid / receipt / etc.)
    }

    mapping(uint256 => StorageSession) public sessions;

    // Immutable config
    IDROPSpaceRegistry public immutable registry;
    IEscrow            public immutable escrow; // may be address(0) to disable escrow

    address public immutable protocolTreasury;
    uint16  public constant  PROTOCOL_FEE_BPS = 30; // 0.3%, immutable

    // Permissionless finalizer tip, tiny incentive for liveness bots.
    // Owner-adjustable up to 1%. Owner may renounce after deploy.
    uint16 public finalizeTipBps = 5; // 0.05%

    // Picker must confirm OR this many seconds must elapse after pick()
    uint64 public constant FINALIZE_WINDOW = 48 hours;

    // Events
    event SessionCreated(
        uint256 indexed storageId,
        uint256 indexed spaceId,
        address indexed dropper,
        address picker
    );
    event Dropped(
        uint256 indexed storageId,
        uint64  t,
        bytes32 evidenceHash,
        string  evidenceCid
    );
    event Picked(
        uint256 indexed storageId,
        uint64  t,
        bytes32 evidenceHash,
        string  evidenceCid,
        uint64  finalizeAfter
    );
    event PickupConfirmed(
        uint256 indexed storageId,
        address picker,
        uint64  t
    );
    event Finalized(
        uint256 indexed storageId,
        address operator,
        bool    byTimeout
    );
    event FinalizeTipSet(uint16 bps);

    // Constructor
    constructor(
        address _registry,
        address _escrow,
        address _protocolTreasury
    )
        ERC721("DROP Storage Session", "DROP")
        Ownable(msg.sender)
    {
        require(_registry         != address(0), "registry-zero");
        require(_protocolTreasury != address(0), "proto-zero");
        // _escrow may be address(0), escrow is optional at protocol level

        registry         = IDROPSpaceRegistry(_registry);
        escrow           = IEscrow(_escrow);
        protocolTreasury = _protocolTreasury;
    }

    // Owner config
    /// @notice Adjust the permissionless finalizer tip. Capped at 1%.
    /// @dev Owner may renounce after deploy to freeze this at its current value.
    function setFinalizeTipBps(uint16 bps) external onlyOwner {
        require(bps < 100, "cap-1%");
        finalizeTipBps = bps;
        emit FinalizeTipSet(bps);
    }

    // Internal helpers
    /// @dev Reverts unless msg.sender is the registered operator of spaceId.
    function _requireStorageOperator(uint256 spaceId) internal view {
        address op = registry.getOperator(spaceId);
        require(op != address(0), "no-space");
        require(msg.sender == op, "not-operator");
    }

    // Core flow
    /// @notice Create a storage session and mint the DROP NFT.
    ///
    /// @param storageId         Protocol-wide unique id (platform-generated).
    /// @param spaceId           Registered storage space to use.
    /// @param picker            Expected picker address. Pass address(0) if unknown.
    ///                          Dropper == picker is explicitly allowed.
    /// @param escrowToken       address(0) = ETH; otherwise ERC20 token address.
    ///                          Ignored when escrowAmount == 0.
    /// @param escrowAmount      If > 0, funds escrow now. If 0, settlement is off-chain.
    /// @param settlementRefHash Optional hash anchoring an off-chain settlement reference.
    function createStorage(
        uint256 storageId,
        uint256 spaceId,
        address picker,
        address escrowToken,
        uint256 escrowAmount,
        bytes32 settlementRefHash
    ) external payable {
        require(_ownerOf(storageId) == address(0), "exists");

        // Validate space exists, prevents dead sessions against unregistered spaces.
        (address operator,,,,,,,,) = registry.spaces(spaceId);
        require(operator != address(0), "no-space");

        // Mint the DROP NFT to the dropper. NFT = session authority token.
        _safeMint(msg.sender, storageId);

        StorageSession storage s = sessions[storageId];
        s.spaceId           = spaceId;
        s.dropper           = msg.sender;
        s.picker            = picker;
        s.state             = State.Created;
        s.createdAt         = uint64(block.timestamp);
        s.settlementRefHash = settlementRefHash;

        if (escrowAmount > 0) {
            require(address(escrow) != address(0), "escrow-disabled");
            s.escrowToken  = escrowToken;
            s.escrowAmount = escrowAmount;
            s.escrowed     = true;

            if (escrowToken == address(0)) {
                require(msg.value == escrowAmount, "bad-value");
                escrow.fund{value: escrowAmount}(storageId, escrowToken, escrowAmount, msg.sender);
            } else {
                require(msg.value == 0, "no-eth");
                escrow.fund(storageId, escrowToken, escrowAmount, msg.sender);
            }
        } else {
            require(msg.value == 0, "no-eth");
        }

        emit SessionCreated(storageId, spaceId, msg.sender, picker);
    }

    /// @notice Operator attests that the item has been received into storage.
    /// @dev Reserves 1 capacity unit. Only the registered space operator may call.
    function drop(
        uint256 storageId,
        bytes32 evidenceHash,
        string calldata evidenceCid
    ) external {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Created, "bad-state");
        _requireStorageOperator(s.spaceId);

        registry.reserveOne(s.spaceId);

        s.dropEvidenceHash = evidenceHash;
        s.dropEvidenceCid  = evidenceCid;
        s.droppedAt        = uint64(block.timestamp);
        s.state            = State.Dropped;

        emit Dropped(storageId, s.droppedAt, evidenceHash, evidenceCid);
    }

    /// @notice Operator attests that the item has left storage.
    /// @dev Releases 1 capacity unit. Starts the 48h settlement window.
    ///      Only the registered space operator may call.
    function pick(
        uint256 storageId,
        bytes32 evidenceHash,
        string calldata evidenceCid
    ) external {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Dropped, "bad-state");
        _requireStorageOperator(s.spaceId);

        registry.releaseOne(s.spaceId);

        s.pickEvidenceHash = evidenceHash;
        s.pickEvidenceCid  = evidenceCid;
        s.pickedAt         = uint64(block.timestamp);
        s.finalizeAfter    = s.pickedAt + FINALIZE_WINDOW;
        s.state            = State.Picked;

        emit Picked(storageId, s.pickedAt, evidenceHash, evidenceCid, s.finalizeAfter);
    }

    /// @notice Picker confirms receipt — Proof of Custody (PoC).
    ///
    /// Primary settlement trigger. Escrow releases to the operator immediately.
    /// If picker == dropper (same-person flow), the dropper calls this themselves.
    ///
    /// @dev If s.picker was set at session creation, only that address may confirm.
    ///      If s.picker == address(0) (open pickup), any address may confirm.
    function confirmPickup(uint256 storageId) external {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Picked, "bad-state");

        if (s.picker != address(0)) {
            require(msg.sender == s.picker, "not-picker");
        }

        emit PickupConfirmed(storageId, msg.sender, uint64(block.timestamp));

        _settle(storageId, false);
    }

    /// @notice Permissionless finalize after 48h timeout.
    ///
    /// Anyone may call once finalizeAfter has elapsed.
    /// Caller receives a small tip from escrow as a liveness incentive.
    function finalize(uint256 storageId) external {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Picked, "bad-state");
        require(block.timestamp >= s.finalizeAfter, "too-early");

        _settle(storageId, true);
    }

    /// @dev Internal: release escrow to operator, or record state-only if no escrow.
    function _settle(uint256 storageId, bool byTimeout) internal {
        StorageSession storage s = sessions[storageId];

        (address operator,,,,,,,,) = registry.spaces(s.spaceId);
        require(operator != address(0), "no-space");

        if (s.escrowed && s.escrowAmount > 0) {
            escrow.releaseWithFees(
                storageId,
                operator,
                address(0), 0,                       // no platform fee at protocol level
                protocolTreasury, PROTOCOL_FEE_BPS,
                msg.sender, byTimeout ? finalizeTipBps : 0
            );
        }

        s.state = State.Finalized;
        emit Finalized(storageId, operator, byTimeout);
    }
}
