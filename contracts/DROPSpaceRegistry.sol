// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title DROPSpaceRegistry
/// @notice Declarative on-chain registry for storage spaces.
///
/// Philosophy:
///   - No pricing, ranking, matching, or identity.
///   - Only: operator address, availability window, capacity, coarse location
///     hash, and a hash commitment to off-chain terms/SLA/pricing.
///   - Capacity reservation and release are gated exclusively to DROPCore
///     to prevent griefing from external callers.
///   - dropCore is set-once after deploy. Owner should renounce afterwards.
///
/// Keep this contract boring and dumb. Everything else is off-chain.
contract DROPSpaceRegistry is Ownable2Step {
    struct Space {
        address operator;           // receives settlement on DROPCore finalize
        bool active;                // operator-controlled enable/disable
        bytes32 coarseLocationHash; // coarse cell hash — never a precise address
        bytes32 termsHash;          // hash(off-chain terms / SLA / pricing / access rules)
        uint64 availableFrom;       // 0 = immediately
        uint64 availableTo;         // 0 = no end
        uint64 capacityTotal;       // total units
        uint64 capacityAvailable;   // currently available units
        string metadataCid;         // optional IPFS/Arweave CID
    }

    mapping(uint256 => Space) public spaces;
    uint256 public nextSpaceId = 1;

    /// @notice DROPCore address. Set-once after deploy.
    address public dropCore;

    event CoreSet(address core);
    event SpaceRegistered(uint256 indexed spaceId, address indexed operator);
    event SpaceUpdated(uint256 indexed spaceId);
    event SpaceStatus(uint256 indexed spaceId, bool active);
    event CapacityChanged(uint256 indexed spaceId, uint64 total, uint64 available);

    modifier onlyCore() {
        require(msg.sender == dropCore, "not-core");
        _;
    }

    modifier onlyOperator(uint256 spaceId) {
        require(msg.sender == spaces[spaceId].operator, "not-operator");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /// @notice Set DROPCore address. Can only be set once.
    /// @dev After setting, owner should renounce ownership.
    function setCore(address core) external onlyOwner {
        require(core != address(0), "core-zero");
        require(dropCore == address(0), "core-already-set");
        dropCore = core;
        emit CoreSet(core);
    }

    /// @notice Convenience getter for operator address, used by DROPCore gating.
    function getOperator(uint256 spaceId) external view returns (address) {
        return spaces[spaceId].operator;
    }

    /// @notice Register a new storage space.
    /// @dev Operator is msg.sender. capacityTotal must be > 0.
    /// @return spaceId The assigned space identifier.
    function registerSpace(
        bytes32 coarseLocationHash,
        bytes32 termsHash,
        uint64 availableFrom,
        uint64 availableTo,
        uint64 capacityTotal,
        string calldata metadataCid
    ) external returns (uint256 spaceId) {
        require(capacityTotal > 0, "cap-zero");
        if (availableTo != 0) require(availableTo > availableFrom, "bad-window");

        spaceId = nextSpaceId++;
        Space storage s = spaces[spaceId];

        s.operator        = msg.sender;
        s.active          = true;
        s.coarseLocationHash = coarseLocationHash;
        s.termsHash       = termsHash;
        s.availableFrom   = availableFrom;
        s.availableTo     = availableTo;
        s.capacityTotal   = capacityTotal;
        s.capacityAvailable = capacityTotal;
        s.metadataCid     = metadataCid;

        emit SpaceRegistered(spaceId, msg.sender);
        emit SpaceUpdated(spaceId);
        emit SpaceStatus(spaceId, true);
        emit CapacityChanged(spaceId, capacityTotal, capacityTotal);
    }

    /// @notice Update non-capacity metadata for a space.
    function updateSpace(
        uint256 spaceId,
        bytes32 coarseLocationHash,
        bytes32 termsHash,
        uint64 availableFrom,
        uint64 availableTo,
        string calldata metadataCid
    ) external onlyOperator(spaceId) {
        if (availableTo != 0) require(availableTo > availableFrom, "bad-window");

        Space storage s = spaces[spaceId];
        s.coarseLocationHash = coarseLocationHash;
        s.termsHash       = termsHash;
        s.availableFrom   = availableFrom;
        s.availableTo     = availableTo;
        s.metadataCid     = metadataCid;

        emit SpaceUpdated(spaceId);
    }

    /// @notice Enable or disable a space.
    function setActive(uint256 spaceId, bool active) external onlyOperator(spaceId) {
        spaces[spaceId].active = active;
        emit SpaceStatus(spaceId, active);
    }

    /// @notice Increase total and available capacity by delta.
    function increaseCapacity(uint256 spaceId, uint64 delta) external onlyOperator(spaceId) {
        require(delta > 0, "delta-zero");
        Space storage s = spaces[spaceId];
        s.capacityTotal     += delta;
        s.capacityAvailable += delta;
        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }

    /// @notice Decrease total capacity by delta. Cannot dip below currently reserved units.
    function decreaseCapacity(uint256 spaceId, uint64 delta) external onlyOperator(spaceId) {
        require(delta > 0, "delta-zero");
        Space storage s = spaces[spaceId];
        require(s.capacityTotal >= delta, "underflow-total");

        uint64 reserved = s.capacityTotal - s.capacityAvailable;
        require(s.capacityTotal - delta >= reserved, "reserved-exceeds");
        require(s.capacityAvailable >= delta, "underflow-avail");

        s.capacityTotal     -= delta;
        s.capacityAvailable -= delta;
        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }

    /// @notice Reserve 1 capacity unit for an active, currently-available space.
    /// @dev Only DROPCore may call. Prevents external griefing.
    function reserveOne(uint256 spaceId) external onlyCore {
        Space storage s = spaces[spaceId];
        require(s.operator != address(0), "no-space");
        require(s.active, "inactive");
        if (s.availableFrom != 0) require(uint64(block.timestamp) >= s.availableFrom, "too-early");
        if (s.availableTo   != 0) require(uint64(block.timestamp) <= s.availableTo,   "too-late");
        require(s.capacityAvailable > 0, "no-capacity");
        unchecked { s.capacityAvailable -= 1; }
        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }

    /// @notice Release 1 capacity unit back to the space.
    /// @dev Only DROPCore may call.
    function releaseOne(uint256 spaceId) external onlyCore {
        Space storage s = spaces[spaceId];
        require(s.operator != address(0), "no-space");
        require(s.capacityAvailable < s.capacityTotal, "nothing-reserved");
        unchecked { s.capacityAvailable += 1; }
        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }
}