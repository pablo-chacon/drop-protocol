// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/DROPCore.sol";
import "../contracts/DROPSpaceRegistry.sol";
import "../contracts/Escrow.sol";

/// @notice Deploy DROP Protocol to mainnet.
///
/// Required env vars:
///   PRIVATE_KEY        = deployer private key
///   PROTOCOL_TREASURY  = Safe multisig that receives 0.3% protocol fee
///
/// Run:
///   forge script script/DeployProtocol.s.sol \
///     --rpc-url $RPC_URL --broadcast --verify
contract DeployProtocol is Script {
    function run() external {
        uint256 deployerKey      = vm.envUint("PRIVATE_KEY");
        address protocolTreasury = vm.envAddress("PROTOCOL_TREASURY");

        require(protocolTreasury != address(0), "PROTOCOL_TREASURY not set");

        vm.startBroadcast(deployerKey);

        // 1. Deploy Escrow
        Escrow escrow = new Escrow();

        // 2. Deploy registry
        DROPSpaceRegistry registry = new DROPSpaceRegistry();

        // 3. Deploy core
        DROPCore core = new DROPCore(
            address(registry),
            address(escrow),
            protocolTreasury
        );

        // 4. Wire: set core on registry and escrow (set-once, cannot be changed)
        registry.setCore(address(core));
        escrow.setDropCore(address(core));

        // 5. No admin surface remains after deployment.
        //    finalizeTipBps is frozen at 5 (0.05%) permanently.
        core.renounceOwnership();
        registry.renounceOwnership();
        escrow.renounceOwnership();

        vm.stopBroadcast();

        // Post-deploy assertions
        // Catch misconfiguration before announcing addresses publicly.
        require(
            registry.dropCore() == address(core),
            "POST-DEPLOY: registry.dropCore mismatch"
        );
        require(
            escrow.dropCore() == address(core),
            "POST-DEPLOY: escrow.dropCore mismatch"
        );
        require(
            address(core.registry()) == address(registry),
            "POST-DEPLOY: core.registry mismatch"
        );
        require(
            address(core.escrow()) == address(escrow),
            "POST-DEPLOY: core.escrow mismatch"
        );
        require(
            core.protocolTreasury() == protocolTreasury,
            "POST-DEPLOY: core.protocolTreasury mismatch"
        );
        require(
            core.PROTOCOL_FEE_BPS() == 30,
            "POST-DEPLOY: unexpected protocol fee"
        );
        require(
            core.owner() == address(0),
            "POST-DEPLOY: core ownership not renounced"
        );
        require(
            registry.owner() == address(0),
            "POST-DEPLOY: registry ownership not renounced"
        );
        require(
            escrow.owner() == address(0),
            "POST-DEPLOY: escrow ownership not renounced"
        );

        // Log addresses
        console2.log("DROP_CORE=",         address(core));
        console2.log("DROP_REGISTRY=",     address(registry));
        console2.log("DROP_ESCROW=",       address(escrow));
        console2.log("PROTOCOL_TREASURY=", protocolTreasury);
    }
}
