// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    function reserveOne(uint256 spaceId) external;
    function releaseOne(uint256 spaceId) external;
}

interface IEscrow {
    function fund(uint256 id, address token, uint256 amount, address payer) external payable;

    function releaseWithFees(
        uint256 id,
        address payTo,
        address platformFeeTo, uint16 platformFeeBps,
        address protocolFeeTo, uint16 protocolFeeBps,
        address caller,        uint16 callerTipBps
    ) external;

    function refund(uint256 id, address to) external;
}

/// @title DROPCore
/// @notice Storage settlement core.
/// - State transitions only: Created -> Dropped -> Picked -> Finalized (-> Disputed optional)
/// - Payment medium is a platform concern:
///   - Optional on-chain escrow via IEscrow for ETH/ERC20 on this chain
///   - Off-chain payments can be anchored via hashes (without escrow)
/// - Immutable protocol fee: 0.5% to protocolTreasury
contract DROPCore is Ownable2Step {
    enum State { None, Created, Dropped, Picked, Finalized, Disputed }

    struct StorageSession {
        uint256 spaceId;

        address platform;      // creator / payer (if escrowed) or initiator (if off-chain)
        address picker;        // optional: who is allowed to pick. zero => anyone can pick (platform risk choice)
        State   state;

        uint64  createdAt;
        uint64  droppedAt;
        uint64  pickedAt;
        uint64  finalizeAfter;

        // Optional evidence anchors (keep neutral: hashes only)
        bytes32 dropCellHash;  // coarse
        bytes32 pickCellHash;  // coarse
        bytes32 evidenceHash;  // generic: photo digest / seal digest / sensor digest
        string  evidenceCid;   // optional off-chain blob CID

        // Optional on-chain escrow
        address escrowToken;   // address(0) => ETH
        uint256 escrowAmount;  // 0 => no on-chain escrow (off-chain settlement)
        bool    escrowed;      // set true if escrow.fund called

        // Optional off-chain settlement reference (hash)
        bytes32 settlementRefHash; // e.g. hash(txid, invoice ref, platform receipt, etc.)
    }

    mapping(uint256 => StorageSession) public sessions;

    IDROPSpaceRegistry public immutable registry;
    IEscrow public immutable escrow; // can be set to address(0) if you deploy without on-chain escrow

    address public immutable protocolTreasury;
    uint16  public constant PROTOCOL_FEE_BPS = 50; // 0.5%

    // Permissionless finalize caller tip (bps of escrow) for liveness, capped small.
    uint16 public finalizeTipBps = 5; // 0.05%

    event SessionCreated(uint256 indexed storageId, uint256 indexed spaceId, address indexed platform, address picker);
    event Dropped(uint256 indexed storageId, uint64 t, bytes32 dropCellHash, bytes32 evidenceHash, string evidenceCid);
    event Picked(uint256 indexed storageId, uint64 t, bytes32 pickCellHash, bytes32 evidenceHash, string evidenceCid);
    event Finalized(uint256 indexed storageId, address operator);
    event Disputed(uint256 indexed storageId, bytes32 reasonHash);
    event Resolved(uint256 indexed storageId, address winner);
    event FinalizeTipSet(uint16 bps);

    constructor(
        address _registry,
        address _escrow,
        address _protocolTreasury
    ) Ownable(msg.sender) {
        require(_registry != address(0), "registry-zero");
        require(_protocolTreasury != address(0), "proto-zero");

        registry = IDROPSpaceRegistry(_registry);
        escrow = IEscrow(_escrow); // may be address(0) to disable escrow usage at protocol level
        protocolTreasury = _protocolTreasury;
    }

    function setFinalizeTipBps(uint16 bps) external onlyOwner {
        require(bps < 100, "cap-1%");
        finalizeTipBps = bps;
        emit FinalizeTipSet(bps);
    }

    /// @notice Create a storage session.
    /// @param storageId Protocol-wide unique id (platform-generated).
    /// @param spaceId Registered space to use.
    /// @param picker Optional address allowed to pick; set 0 for permissionless pick.
    /// @param escrowToken address(0)=ETH, otherwise ERC20. Ignored if escrowAmount==0.
    /// @param escrowAmount If >0, funds escrow now via IEscrow. If 0, settlement is off-chain.
    /// @param settlementRefHash Optional hash anchoring off-chain settlement reference.
    function createStorage(
        uint256 storageId,
        uint256 spaceId,
        address picker,
        address escrowToken,
        uint256 escrowAmount,
        bytes32 settlementRefHash
    ) external payable {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.None, "exists");

        // Validate space exists (operator != 0) to avoid dead sessions.
        (address operator,,,,,,,,) = registry.spaces(spaceId);
        require(operator != address(0), "no-space");

        s.spaceId = spaceId;
        s.platform = msg.sender;
        s.picker = picker;
        s.state = State.Created;
        s.createdAt = uint64(block.timestamp);
        s.settlementRefHash = settlementRefHash;

        if (escrowAmount > 0) {
            // Escrow is optional. If you want on-chain settlement: fund it now.
            // If escrow contract is not deployed/used, deploy with non-zero escrow address.
            require(address(escrow) != address(0), "escrow-disabled");
            s.escrowToken = escrowToken;
            s.escrowAmount = escrowAmount;
            s.escrowed = true;

            if (escrowToken == address(0)) {
                require(msg.value == escrowAmount, "bad-value");
                escrow.fund{value: escrowAmount}(storageId, escrowToken, escrowAmount, msg.sender);
            } else {
                require(msg.value == 0, "no-eth");
                escrow.fund(storageId, escrowToken, escrowAmount, msg.sender);
            }
        } else {
            // Off-chain settlement. Must not attach ETH.
            require(msg.value == 0, "no-eth");
        }

        emit SessionCreated(storageId, spaceId, msg.sender, picker);
    }

    /// @notice Mark the item/container as dropped into the storage space.
    /// @dev Reserves 1 unit of space capacity.
    function drop(
        uint256 storageId,
        bytes32 dropCellHash,
        bytes32 evidenceHash,
        string calldata evidenceCid
    ) external {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Created, "bad-state");

        // Reserve capacity at the moment of drop.
        registry.reserveOne(s.spaceId);

        s.dropCellHash = dropCellHash;
        s.evidenceHash = evidenceHash;
        s.evidenceCid  = evidenceCid;
        s.droppedAt = uint64(block.timestamp);
        s.state = State.Dropped;

        emit Dropped(storageId, s.droppedAt, dropCellHash, evidenceHash, evidenceCid);
    }

    /// @notice Mark the item/container as picked from storage.
    /// @dev Releases 1 unit back to the space capacity.
    function pick(
        uint256 storageId,
        bytes32 pickCellHash,
        bytes32 evidenceHash,
        string calldata evidenceCid
    ) external {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Dropped, "bad-state");
        if (s.picker != address(0)) require(msg.sender == s.picker, "not-picker");

        // Release capacity as soon as the item leaves storage.
        registry.releaseOne(s.spaceId);

        s.pickCellHash = pickCellHash;
        s.evidenceHash = evidenceHash;
        s.evidenceCid  = evidenceCid;
        s.pickedAt = uint64(block.timestamp);

        // Liveness window for finalize: allow immediate finalize after pick, but support delayed finalize patterns.
        s.finalizeAfter = s.pickedAt; // can be adjusted if you want a delay

        s.state = State.Picked;

        emit Picked(storageId, s.pickedAt, pickCellHash, evidenceHash, evidenceCid);
    }

    /// @notice Finalize settlement. Permissionless if escrowed (caller gets a tiny tip).
    /// @dev If no escrow was used, this only finalizes state (the settlement happened off-chain).
    function finalize(uint256 storageId) external {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Picked, "bad-state");
        require(block.timestamp >= s.finalizeAfter, "too-early");

        // Determine operator payout address from registry at finalize-time.
        (address operator,,,,,,,,) = registry.spaces(s.spaceId);
        require(operator != address(0), "no-space");

        if (s.escrowed && s.escrowAmount > 0) {
            // Platform fee is always 0 in DROP (platform economics are off-chain).
            // Protocol fee is immutable 0.5%.
            escrow.releaseWithFees(
                storageId,
                operator,
                address(0),        0,
                protocolTreasury,  PROTOCOL_FEE_BPS,
                msg.sender,        finalizeTipBps
            );
        }

        s.state = State.Finalized;
        emit Finalized(storageId, operator);
    }

    /// @notice Dispute after drop or pick (platform-controlled).
    /// @dev Keeps protocol minimal; arbitration is off-chain. Owner can resolve if you want a last-resort.
    function dispute(uint256 storageId, bytes32 reasonHash) external {
        StorageSession storage s = sessions[storageId];
        require(msg.sender == s.platform, "not-platform");
        require(s.state == State.Dropped || s.state == State.Picked, "bad-state");
        s.state = State.Disputed;
        emit Disputed(storageId, reasonHash);
    }

    /// @notice Owner resolution hook (optional governance at deployment level).
    /// @dev If you want absolute immutability/no admin, deploy with an owner you burn/renounce.
    function resolve(uint256 storageId, address winner) external onlyOwner {
        StorageSession storage s = sessions[storageId];
        require(s.state == State.Disputed, "bad-state");

        (address operator,,,,,,,,) = registry.spaces(s.spaceId);
        require(operator != address(0), "no-space");

        // If escrowed, either pay operator (winner==operator) or refund platform.
        if (s.escrowed && s.escrowAmount > 0) {
            if (winner == operator) {
                escrow.releaseWithFees(
                    storageId,
                    operator,
                    address(0),        0,
                    protocolTreasury,  PROTOCOL_FEE_BPS,
                    msg.sender,        0
                );
            } else {
                escrow.refund(storageId, s.platform);
            }
        }

        s.state = State.Finalized;
        emit Resolved(storageId, winner);
        emit Finalized(storageId, operator);
    }
}
