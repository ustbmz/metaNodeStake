# MetaNodeStake

用 Hardhat 实现的 MetaNode 质押合约。用户把 ETH 或 ERC20 存进资金池，合约按区块和池子权重发放 MetaNode。取出本金要先解锁，再单独提现。奖励代币由部署者预先转入质押合约，合约本身不增发。

当前完成了前两步：奖励代币，以及质押合约的可升级骨架。开池、计奖、质押、提现和领奖还没写。

## 技术栈

- Solidity 0.8.22，优化器关闭
- Hardhat 2 与 `@nomicfoundation/hardhat-toolbox`
- OpenZeppelin Contracts 5，以及 `@openzeppelin/hardhat-upgrades`
- 质押合约使用 UUPS 代理。依赖声明为 `^5.0.2`，当前安装的是 5.6

## 目录

```text
contracts/MetaNode.sol        奖励代币 MetaNodeToken
contracts/MetaNodeStake.sol   质押合约骨架
scripts/deployMetaNode.js     本地或指定网络部署奖励代币
test/MetaNode.js              奖励代币测试
test/MetaNodeStake.js         初始化与权限测试
hardhat.config.js             编译器与 Sepolia 配置
.env.example                  环境变量模板
```

`node_modules`、`cache`、`artifacts` 和 `.env` 不进入 Git。

## 本地运行

```bash
npm install
npx hardhat test
npx hardhat run scripts/deployMetaNode.js
```

`npx hardhat test` 在内存链上跑，不需要私钥。部署到 Sepolia 时，复制 `.env.example` 为 `.env` 并填入：

```text
SEPOLIA_RPC_URL=
PRIVATE_KEY=
ETHERSCAN_API_KEY=
```

没有 `PRIVATE_KEY` 时，Sepolia 账户列表为空，本地编译和测试不受影响。

## 目标业务

完成后的用户路径是：

1. 管理员部署 `MetaNodeToken`，再通过代理部署 `MetaNodeStake`，并把奖励代币转入质押合约。
2. 管理员添加资金池。0 号池固定是 ETH，之后的池是 ERC20。
3. 用户 `depositETH` 或 `deposit` 存入本金，开始计奖励。
4. 用户 `unstake` 申请解质押。本金进入队列，等到 `unlockBlocks` 之后，`withdraw` 才把 ETH 或 ERC20 转回。
5. 用户 `claim` 领取 MetaNode。领取奖励和取回本金是两笔交易。

每个区块的全网产出是 `MetaNodePerBlock`。某个池分到的数量是全网产出乘以 `poolWeight / totalPoolWeight`，池内再按用户质押占比分配。有效区间是 `[startBlock, endBlock)`。

用户在某个池子里当前可领的数量是：

```text
stAmount * accMetaNodePerST / 1e18 - finishedMetaNode + pendingMetaNode
```

`accMetaNodePerST` 乘过 `1e18`，用来减少除法丢精度。`finishedMetaNode` 是上次结清时的基线，`pendingMetaNode` 是已经切下来、还没转出的奖励。这两个字段现在只占存储，计算函数还没实现。

## 第一步：Hardhat 工程和奖励代币

工程按 Hardhat JavaScript 项目的目录手写，包含 `package.json`、`hardhat.config.js`、合约、测试和部署脚本。

`MetaNodeToken` 继承 OpenZeppelin 的 `ERC20`。构造函数把名称设为 `MetaNodeToken`，符号设为 `MetaNode`，并向部署者铸造 1000 万枚。这里的 `ether` 表示 `10^18`，所以总量是 `10000000 * 10^18`。合约没有额外的 `mint`，部署之后总量不再增加。

```solidity
contract MetaNodeToken is ERC20 {
    constructor() ERC20("MetaNodeToken", "MetaNode") {
        _mint(msg.sender, 10_000_000 ether);
    }
}
```

这是奖励币，不是质押合约。质押合约以后只持有它的地址，用户领取时从质押合约的余额里转出。余额不够时，奖励就转不出去，因此部署者需要事先把 MetaNode 转进质押合约。

`test/MetaNode.js` 检查总供应量和部署者余额都是 1000 万枚，符号是 `MetaNode`。

## 第二步：质押合约骨架

`MetaNodeStake` 目前只有角色、存储和初始化。它继承四份 OpenZeppelin 可升级合约：

| 父合约 | 作用 |
| --- | --- |
| `Initializable` | 用 `initialize` 代替构造函数保存业务参数，并保证只执行一次 |
| `UUPSUpgradeable` | 实现合约可以通过代理升级。升级入口在实现合约里 |
| `AccessControlUpgradeable` | 按角色限制管理员操作 |
| `PausableUpgradeable` | 预留全局暂停。当前还没有对外的暂停函数 |

### 为什么有两个地址

UUPS 部署后有两个合约：

- 实现合约保存代码。它的构造函数调用 `_disableInitializers()`，把初始化版本写成 `uint64` 的最大值。之后任何人不能再对实现合约调用 `initialize`。
- 代理合约是用户以后交互的地址，数据存在代理里。`upgrades.deployProxy` 部署代理时调用 `initialize`，把奖励代币和产出参数写进代理存储。

构造函数只在实现合约部署时执行，写不进代理的存储，所以业务参数放在 `initialize` 里。`_disableInitializers` 来自 OpenZeppelin 的 `Initializable`，定义在 `@openzeppelin/contracts/proxy/utils/Initializable.sol`。`contracts-upgradeable` 里的同名文件只是别名。API 说明见 [Initializable](https://docs.openzeppelin.com/contracts/5.x/api/proxy#Initializable)。

OpenZeppelin 5.6 已经去掉空的 `__UUPSUpgradeable_init()`，因此 `initialize` 里只调用 `__AccessControl_init()` 和 `__Pausable_init()`。暂停状态的初始值是未暂停。

### 初始化参数

`initialize(rewardToken, startBlock, endBlock, metaNodePerBlock)` 要求 `startBlock <= endBlock`，并且每块产量大于 0。通过后，调用者同时获得三个角色：

| 角色 | 常量 | 能做的事 |
| --- | --- | --- |
| 默认管理员 | `DEFAULT_ADMIN_ROLE` | 授予和撤销角色 |
| 管理员 | `ADMIN_ROLE = keccak256("admin_role")` | 现在可以调用 `setMetaNode`。开池和改参数以后也归它 |
| 升级 | `UPGRADE_ROLE = keccak256("upgrade_role")` | `_authorizeUpgrade` 只认这个角色 |

`ETH_PID` 固定为 0，留给以后的 ETH 池。`setMetaNode` 是目前唯一的管理员写函数，会发出 `SetMetaNode`。没有该角色的地址会得到 `AccessControlUnauthorizedAccount`。代理上的第二次 `initialize` 会得到 `InvalidInitialization`。

### 存储

可升级合约的变量顺序以后不能在中间插入，所以最终要用的状态在这一步全部声明。新增字段只能加在末尾。

`Pool` 保存一个资金池：

| 字段 | 含义 |
| --- | --- |
| `stTokenAddress` | 质押代币地址。ETH 池为 `address(0)` |
| `poolWeight` | 该池在全网产出中的权重 |
| `lastRewardBlock` | 上次结算奖励的区块 |
| `accMetaNodePerST` | 每单位质押代币累计的 MetaNode，已乘 `1e18` |
| `stTokenAmount` | 池内正在计息的总量 |
| `minDepositAmount` | 最小质押数量 |
| `unstakeLockedBlocks` | 解质押后需要等待的区块数 |

`UnstakeRequest` 保存一笔解质押：`amount` 是本金，`unlockBlocks` 是可以取走的区块高度。

`User` 按 `poolId + 用户地址` 存储：

| 字段 | 含义 |
| --- | --- |
| `stAmount` | 仍在计息的本金 |
| `finishedMetaNode` | 已结清的奖励基线 |
| `pendingMetaNode` | 已算出、等待 `claim` 的奖励 |
| `requests` | 解质押队列 |

`User` 包含动态数组，公开 getter 只返回前三个数值字段，不返回 `requests`。

全局变量按这个顺序排列：`startBlock`、`endBlock`、`MetaNodePerBlock`、`withdrawPaused`、`claimPaused`、`MetaNode`、`totalPoolWeight`、`pool`、`user`。初始化完成后池数组为空，读取 `pool(0)` 会回滚。

### 这一步的测试

`test/MetaNodeStake.js` 用 `upgrades.deployProxy` 部署，初始参数是区块 100 到 1000、每块 `0.02` 枚 MetaNode。它覆盖四件事：

- 代理记下产出参数，部署者拥有三个角色，用户仓位为零。
- 代理不能初始化第二次。
- 结束区块早于开始区块时部署失败，错误信息是 `invalid parameters`。
- 没有管理员角色的地址不能更换奖励代币。

## 后续步骤

3. 管理员开池、修改权重、最小质押额和解锁区块数。第一个池必须是 ETH。
4. 实现 `updatePool` 和 `pendingMetaNode`。
5. 实现 `depositETH` 和 ERC20 `deposit`。
6. 实现 `unstake` 与 `withdraw`。
7. 实现 `claim`。
