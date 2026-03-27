// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Escrow
/// @notice Reusable escrow for DROP Protocol (and sibling protocols).
/// @dev Only DROPCore (dropCore) may call fund/release/refund.
///      dropCore is set-once after deploy; owner should renounce afterwards.
contract Escrow is Ownable2Step, ReentrancyGuard {
    /// @notice Address of DROPCore. Set once, then immutable in practice.
    address public dropCore;

    struct Ledger {
        address token;   // address(0) = ETH
        uint256 amount;
        address payer;
        bool paid;
        bool released;
    }

    mapping(uint256 => Ledger) public ledgers;

    event CoreSet(address core);

    modifier onlyCore() {
        require(msg.sender == dropCore, "not-core");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /// @notice Set DROPCore address. Can only be set once.
    /// @dev After setting, owner should renounce ownership.
    function setDropCore(address core) external onlyOwner {
        require(core != address(0), "core-zero");
        require(dropCore == address(0), "core-already-set");
        dropCore = core;
        emit CoreSet(core);
    }

    /// @notice Fund escrow for a storage session.
    /// @dev For ETH: msg.value must equal amount.
    ///      For ERC20: payer must have pre-approved this contract.
    function fund(
        uint256 id,
        address token,
        uint256 amount,
        address payer
    ) external payable onlyCore nonReentrant {
        Ledger storage L = ledgers[id];
        require(!L.paid, "already-funded");

        L.token = token;
        L.amount = amount;
        L.payer = payer;
        L.paid = true;

        if (token == address(0)) {
            require(msg.value == amount, "bad-value");
        } else {
            require(msg.value == 0, "no-eth");
            require(
                IERC20(token).transferFrom(payer, address(this), amount),
                "transferFrom-failed"
            );
        }
    }

    function _sendEth(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        require(ok, "eth-send-failed");
    }

    /// @notice Release escrowed funds with fee distribution.
    /// @param id           Storage session id.
    /// @param operator     Storage provider — receives net settlement.
    /// @param platformFeeTo  Platform treasury (address(0) = skip).
    /// @param platformFeeBps Platform fee in basis points.
    /// @param protocolFeeTo  Protocol treasury.
    /// @param protocolFeeBps Protocol fee in basis points (immutable 0.5% enforced by DROPCore).
    /// @param caller        Permissionless finalizer — receives tip.
    /// @param callerTipBps  Finalizer tip in basis points.
    function releaseWithFees(
        uint256 id,
        address operator,
        address platformFeeTo,
        uint16 platformFeeBps,
        address protocolFeeTo,
        uint16 protocolFeeBps,
        address caller,
        uint16 callerTipBps
    ) external onlyCore nonReentrant {
        Ledger storage L = ledgers[id];
        require(L.paid && !L.released, "bad-ledger");
        L.released = true;

        require(
            platformFeeBps < 10000 && protocolFeeBps < 10000 && callerTipBps < 10000,
            "bps-overflow"
        );
        require(
            uint32(platformFeeBps) + uint32(protocolFeeBps) + uint32(callerTipBps) <= 10000,
            "total-bps-overflow"
        );

        uint256 p = (L.amount * platformFeeBps) / 10000;
        uint256 r = (L.amount * protocolFeeBps) / 10000;
        uint256 t = (L.amount * callerTipBps) / 10000;
        uint256 v = L.amount - p - r - t;

        if (L.token == address(0)) {
            if (p > 0) _sendEth(platformFeeTo, p);
            if (r > 0) _sendEth(protocolFeeTo, r);
            if (t > 0) _sendEth(caller, t);
            _sendEth(operator, v);
        } else {
            if (p > 0) require(IERC20(L.token).transfer(platformFeeTo, p), "xferP");
            if (r > 0) require(IERC20(L.token).transfer(protocolFeeTo, r), "xferR");
            if (t > 0) require(IERC20(L.token).transfer(caller, t), "xferT");
            require(IERC20(L.token).transfer(operator, v), "xferV");
        }
    }

    /// @notice Refund escrowed funds to a given address (dispute resolution).
    function refund(uint256 id, address to) external onlyCore nonReentrant {
        Ledger storage L = ledgers[id];
        require(L.paid && !L.released, "bad-ledger");
        L.released = true;

        if (L.token == address(0)) {
            _sendEth(to, L.amount);
        } else {
            require(IERC20(L.token).transfer(to, L.amount), "xfer-failed");
        }
    }

    /// @dev Reject direct ETH sends.
    receive() external payable {
        revert("no-direct-eth");
    }
}