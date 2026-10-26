// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MetaNode 奖励代币
/// @notice 质押合约不增发奖励。部署时把总量铸给部署者，再由部署者转入质押合约。
contract MetaNodeToken is ERC20 {
    constructor() ERC20("MetaNodeToken", "MetaNode") {
        _mint(msg.sender, 10_000_000 ether);
    }
}
