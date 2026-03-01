// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title DROPSpaceRegistry
/// @notice Declarative registry for storage spaces/capacity.
/// - No pricing, ranking, identity, or matching.
/// - Only: availability + coarse location hash + terms commitment.
/// - Capacity reservation/release is performed by DROPCore (the "core").
/// @dev Keep this contract boring and dumb. Everything else is off-chain.
contract DROPSpaceRegistry is Ownable2Step {
    struct Space {
        address operator; // space operator (receives settlement off DROPCore finalize)
        bool active; // space enabled/disabled by operator
        bytes32 coarseLocationHash; // coarse cell hash; never a precise address
        bytes32 termsHash; // hash(commitment) of off-chain terms/rules/pricing/SLA/access
        uint64 availableFrom; // optional; 0 means "immediately"
        uint64 availableTo; // optional; 0 means "no end"
        uint64 capacityTotal; // total units
        uint64 capacityAvailable; // available units
        string metadataCid; // optional: IPFS/Arweave CID (or empty)
    }

    mapping(uint256 => Space) public spaces;
    uint256 public nextSpaceId = 1;

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

    /// @notice Helper getter for operator address, used by DROPCore gating.
    function getOperator(uint256 spaceId) external view returns (address) {
        return spaces[spaceId].operator;
    }

    /// @notice Set DROPCore address (updatable by owner).
    /// @dev If you want to freeze this, renounce ownership after setting.
    function setCore(address core) external onlyOwner {
        require(core != address(0), "core-zero");
        dropCore = core;
        emit CoreSet(core);
    }

    /// @notice Register a new space. Returns the assigned spaceId.
    /// @dev Operator is msg.sender. Capacity must be > 0.
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

        s.operator = msg.sender;
        s.active = true;
        s.coarseLocationHash = coarseLocationHash;
        s.termsHash = termsHash;
        s.availableFrom = availableFrom;
        s.availableTo = availableTo;
        s.capacityTotal = capacityTotal;
        s.capacityAvailable = capacityTotal;
        s.metadataCid = metadataCid;

        emit SpaceRegistered(spaceId, msg.sender);
        emit SpaceUpdated(spaceId);
        emit SpaceStatus(spaceId, true);
        emit CapacityChanged(spaceId, capacityTotal, capacityTotal);
    }

    /// @notice Update non-capacity fields for a space.
    /// @dev Operator-controlled.
    function updateSpace(
        uint256 spaceId,
        bytes32 coarseLocationHash,
        bytes32 termsHash,
        uint64 availableFrom,
        uint64 availableTo,
        string calldata metadataCid
    ) external onlyOperator(spaceId) {
        Space storage s = spaces[spaceId];
        if (availableTo != 0) require(availableTo > availableFrom, "bad-window");

        s.coarseLocationHash = coarseLocationHash;
        s.termsHash = termsHash;
        s.availableFrom = availableFrom;
        s.availableTo = availableTo;
        s.metadataCid = metadataCid;

        emit SpaceUpdated(spaceId);
    }

    /// @notice Enable/disable space.
    function setActive(uint256 spaceId, bool active) external onlyOperator(spaceId) {
        spaces[spaceId].active = active;
        emit SpaceStatus(spaceId, active);
    }

    /// @notice Increase total capacity (and available capacity) by delta.
    /// @dev Operator-controlled.
    function increaseCapacity(uint256 spaceId, uint64 delta) external onlyOperator(spaceId) {
        require(delta > 0, "delta-zero");
        Space storage s = spaces[spaceId];

        unchecked {
            s.capacityTotal += delta;
            s.capacityAvailable += delta;
        }

        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }

    /// @notice Decrease total capacity by delta.
    /// @dev Operator-controlled. Must not dip below reserved capacity.
    function decreaseCapacity(uint256 spaceId, uint64 delta) external onlyOperator(spaceId) {
        require(delta > 0, "delta-zero");
        Space storage s = spaces[spaceId];

        require(s.capacityTotal >= delta, "underflow-total");

        // reserved = total - available
        uint64 reserved = s.capacityTotal - s.capacityAvailable;
        require(s.capacityTotal - delta >= reserved, "reserved-exceeds");

        s.capacityTotal -= delta;

        // available reduces by same delta (since reserved fixed)
        require(s.capacityAvailable >= delta, "underflow-avail");
        s.capacityAvailable -= delta;

        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }

    /// @notice Reserve 1 unit of capacity for an active, currently-available space.
    /// @dev Only DROPCore may reserve/release. This prevents direct griefing.
    function reserveOne(uint256 spaceId) external onlyCore {
        Space storage s = spaces[spaceId];
        require(s.operator != address(0), "no-space");
        require(s.active, "inactive");
        if (s.availableFrom != 0) require(uint64(block.timestamp) >= s.availableFrom, "too-early");
        if (s.availableTo != 0) require(uint64(block.timestamp) <= s.availableTo, "too-late");
        require(s.capacityAvailable > 0, "no-capacity");

        unchecked {
            s.capacityAvailable -= 1;
        }

        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }

    /// @notice Release 1 unit of capacity back to the space.
    function releaseOne(uint256 spaceId) external onlyCore {
        Space storage s = spaces[spaceId];
        require(s.operator != address(0), "no-space");
        require(s.capacityAvailable < s.capacityTotal, "nothing-reserved");

        unchecked {
            s.capacityAvailable += 1;
        }

        emit CapacityChanged(spaceId, s.capacityTotal, s.capacityAvailable);
    }
}