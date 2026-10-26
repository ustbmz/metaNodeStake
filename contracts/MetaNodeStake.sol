// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @title MetaNode 质押合约
/// @notice 这一版只有骨架：角色、存储和初始化。开池、计奖、质押、提现后面再加。
contract MetaNodeStake is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");

    /// @notice 0 号池固定是 ETH 池。
    uint256 public constant ETH_PID = 0;

    /// @notice 一个资金池的配置和计奖状态。
    struct Pool {
        address stTokenAddress;
        uint256 poolWeight;
        uint256 lastRewardBlock;
        uint256 accMetaNodePerST;
        uint256 stTokenAmount;
        uint256 minDepositAmount;
        uint256 unstakeLockedBlocks;
    }

    /// @notice 一笔解质押请求。本金要等到 unlockBlocks 之后才能取走。
    struct UnstakeRequest {
        uint256 amount;
        uint256 unlockBlocks;
    }

    /// @notice 某个用户在某个池子里的仓位。
    /// @dev finishedMetaNode 是已结清的奖励基线，不是已经打到钱包的数量。
    struct User {
        uint256 stAmount;
        uint256 finishedMetaNode;
        uint256 pendingMetaNode;
        UnstakeRequest[] requests;
    }

    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public MetaNodePerBlock;

    bool public withdrawPaused;
    bool public claimPaused;

    IERC20 public MetaNode;

    uint256 public totalPoolWeight;
    Pool[] public pool;
    mapping(uint256 => mapping(address => User)) public user;

    event SetMetaNode(IERC20 indexed MetaNode);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice 通过代理部署时调用一次。直接部署的实现合约已被构造函数锁死。
    function initialize(
        IERC20 _MetaNode,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _MetaNodePerBlock
    ) public initializer {
        require(
            _startBlock <= _endBlock && _MetaNodePerBlock > 0,
            "invalid parameters"
        );

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        setMetaNode(_MetaNode);

        startBlock = _startBlock;
        endBlock = _endBlock;
        MetaNodePerBlock = _MetaNodePerBlock;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADE_ROLE) {}

    /// @notice 更换奖励代币。只有管理员可以调用。
    function setMetaNode(IERC20 _MetaNode) public onlyRole(ADMIN_ROLE) {
        MetaNode = _MetaNode;
        emit SetMetaNode(MetaNode);
    }
}
