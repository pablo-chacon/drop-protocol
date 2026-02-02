// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/DROPCore.sol";
import "../contracts/DROPSpaceRegistry.sol";
import "../contracts/Escrow.sol";

contract DeployProtocol is Script {
  function run() external {
    uint256 deployerKey = vm.envUint("PRIVATE_KEY");
    address protocolTreasury = vm.envAddress("PROTOCOL_TREASURY");

    vm.startBroadcast(deployerKey);

    Escrow escrow = new Escrow();
    DROPSpaceRegistry registry = new DROPSpaceRegistry();
    DROPCore core = new DROPCore(
      address(registry),
      address(escrow),
      protocolTreasury
    );

    registry.setCore(address(core));
    escrow.setParcelCore(address(core));

    vm.stopBroadcast();

    console2.log("DROP_CORE=", address(core));
    console2.log("DROP_REGISTRY=", address(registry));
    console2.log("ESCROW=", address(escrow));
    console2.log("PROTOCOL_TREASURY=", protocolTreasury);
  }
}
