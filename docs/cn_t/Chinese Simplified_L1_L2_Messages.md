---
id: L1_L2_层之间的通信
title: 层之间消息传递
sidebar_label: 层之间消息传递
---

## 标准Arbitrum交易：来自客户端的调用

Arbitrum上标准的客户端调用的交易是通过EthBridge中Inbox.sendL2Message来实现的

```solidity
function sendL2Message(address chain, bytes calldata messageData) external;

```

正如在[Tx call生命周期] （../7_杂项/3_Tx call生命周期.md）中描述的那样，通常大部分调用都会走聚合器并被批量处理。

不过，Arbitrum协议也支持在L1和L2之间传递信息。

最常见的跨链通信目的是充值和提现；不过这只是Arbitrum支持的通用型跨链合约调用中的特定一种 本章节描述了这些通用协议；深入解释，请见洞悉Arbitrum: 桥接。

## 以太坊到Arbitrum：Retryable Tickets（可重试票）

可重试票据是 Arbitrum 协议的规范方法，此方法将通用消息从以太坊传递到 Arbitrum 可重试票据工作机理如下：一条L1交易提交到了收件箱中，其内容为向L2进行一笔转账（包含了calldata，callvalue，以及gas info）如果有提供任意数量的gas，L2上的交易会自动执行。在乐观的/正常的情况下，L2上的交易会立即成功。 如果该交易第一次没有执行成功，在L2上会进入一个『retry buffer重试缓存』。这意味着在一段时间内(与该链的挑战期有关，大约为一周)，任何人都可以通过再次执行来尝试赎回该L2交易票证。

### 动机

可重试票证的设计是为了完美地处理跨链消息传递中各种潜在的棘手问题。

- 多付 L2 Gas费用： L1 合约必须为 L2 交易的执行提供 Gas 费用；如果 L1 一方多付了 Gas 费用，这就会引发如何处理多余的 ETH 费用问题。

- L2交易的恢复--打破原子性。对于许多L1到L2交易的用例来说，两层的状态更新都是原子性的，也就是说，如果L1端成功了，就能保证L2最终也会成功。 这里的典型例子是代币存款：在L1，代币被托管在一些合同中，并向L2发送一个消息以铸造一些相应的代币。 如果L1端成功了，而L2端被恢复了，那么用户只能失去他们的代币（也就是把代币捐给了桥梁合约）。

- L2交易还原--处理L2 callvalue。L1方必须为L2交易的callvalue提供以太币（通过存款）；如果L2交易被恢复，这就产生了如何处理这个亏损的以太币的问题。

以上发生的所有问题，可重试票可以非常完美地处理！

### 交易类型/术语

| Txn 类型 | 描述                                          | 状态                                                        | Tx ID                                                                  |
| ------ | ------------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------- |
| 可重试的票  | 位于重试缓冲区中的准事务，有一个可以执行的期限，即 "赎回"              | 包含消息时发出；如果用户提供足够的 ETH 来支付基本费用 + callvalue，则成功，否则失败。       | _keccak256(zeroPad(l2ChainId), zeroPad(BitFlipedinboxSequenceNumber))_ |
| 赎回 Txn | 可重试的票证被成功赎回时；看起来像正常的L2交易。                   | 用户启动或通过自动兑换，成功兑换可重试票证后发出。                                 | _keccak256(zeroPad(retryable-ticket-id), 0)_                           |
| 自动兑换记录 | 准交易 ArbOS 会自动创建，收到 ArbGas 提交时，立即尝试兑换可重试的票证。 | 尝试 / 发出 iff gas*gas-price > 0。 如果失败，可重试票证将保留在重试缓冲区中，继续等待。 | \_keccak256(zeroPad(retryable-ticket-id), 1)                         |

### 可重试票合约 API

通过调用 [Inbox.createRetrableTicket](./sol_contract_docs/md_docs/arb-bridge-eth/bridge/Inbox.md) 创建可重试票证。 其他涉及可重试票证的操作通过[ArbRetlyableTicket](./sol_contract_docs/md_docs/arb-os/arbos/builtin/ArbRetryableTx.md) 预编译接口在 L2 地址 0x000000000000000000000000006E 预编译。 (在正常情况下无需使用此合同)

### 参数：

在创建可重试票证时，L1 必须将总共 10 个参数，传递给 L2。

其中 5 个与分配的 ETH/Gas 有关：

- DepositValue（存款价值）：从L1到L2存入的ETH总量。
- CallValue（呼叫值）：L2交易的调用值。
- GasPrice（Gas 价格）：用 L2 Gas 标准价格出价，将会立即执行(可通过标准的eth\*gasPrice RPC查询)。
- MaxGas（最大 Gas）：立即执行 L2 尝试的最快 Gas 限制（可以通过 _NodeInterface.estimateRetryableTicket* 估算）。
- **MaxSubmissionCost:** Amount of ETH allocated to pay for the base submission fee. 基本提交费用是可重试交易独有的参数；向用户收取基本提交费用，以支付将票证的呼叫数据保存在重试缓冲区中的存储成本。 (当前的基础提交费用，可通过 ArbRetryableTx.getSubmissionPrice 查询)。

直观地说：如果用户不想立即赎回，他们应该提供至少 `CallValue + MaxSubmission成本` 的存款价值。 If they do desire immediate execution, they should provide a DepositValue of at least `CallValue + MaxSubmissionCost + (GasPrice x MaxGas).`

### Other Parameters

- **Destination Address:** Address from which transaction will be initiated on L2.
- **Credit-Back Address:** Address to which all excess gas is credited on L2; i.e., excess ETH for base submission cost (`MaxSubmissionCost - ActualSubmissionCostPaid`) and excess ETH provided for L2 execution (`(GasPrice x MaxGas) - ActualETHSpentInExecution`).
- **Beneficiary:** Address to which CallValue will be credited to on L2 if the retryable ticket times out or is cancelled. The Beneficiary is also the address with the right to cancel a Retryable Ticket (if the ticket hasn’t been redeemed yet). `Calldata:` data encoding the L2 contract call. `Calldata Size:` CallData size.

### Important Note About Base Submission Fee

If an L1 transaction underpays for a retryable ticket's base submission free, the retryable ticket creation on L2 simply fails. Given that this potentially breaks the atomicity of the L1 / L2 transactions, applications should avoid this scenario. The current base submission fee returned by `ArbRetryableTx.getSubmissionPrice` increases once every 24 hour period by at most 50% of its current value. Since any amount overpaid will be credited to the `credit-back-address`, it is highly recommended that applications judiciously overpay relative to the current price.

In a future release, the base submission fee will be calculated using the 1559 `BASE_FEE` and collected directly at L1; underpayment will simply result in the L1 transaction reverting, thus avoiding the complications above entirely.

### Retryable Transaction Lifecycle:

When a retryable ticket is initiated from the L1, the following things take place:

- DepositValue is credited to the sender’s account on L2.
  - If the L2 account's balance (which now includes the DepositValue) is less than MaxSubmissionCost + Callvalue, the Retryable Ticket creation fails.
  - If MaxSubmissionCost is less than the submission fee, the Retryable Ticket creation fails.
- Submission fee is collected: submission fee is deducted from the sender’s L2 account; MaxSubmissionCost - submission fee is credited to Credit-Back Address.

- Callvalue is deducted from sender’s L2 account and a Retryable Ticket is successfully created.
  - If the sender has insufficient funds to cover the callvalue (even after the DepositValue has been credited), the Retryable Ticket fails.
- If MaxGas and MaxPrice are both > 0, an immediate redemption will be attempted:

- MaxGas x MaxPrice is credited to the Credit-Back Address.
- The retryable ticket is automatically executed —i.e., the transaction encoded in Calldata with Callvalue — with gas provided by the Credit-Back Address.
- If it succeeds, a successful Immediate-Redeem Txn is emitted along with a successful Redemption Transaction. Any excess gas remains in the Credit-Back Address.
- If it reverts, a failed Immediate-Redeem Txn is emitted, and the Retryable Ticket is placed in the retry-buffer. ...Otherwise, the Retryable Ticket goes straight into the retry buffer, and no Immediate-Redeem Txn is ever emitted.

Any user can redeem a Retryable Ticket in the retry buffer (before it expires) by calling ArbRetryableTicket.redeem(Redemption-TxID). The user provides gas the way they would a normal L2 transaction.

If the Retryable Ticket is cancelled or expires before it is redeemed, Callvalue is credited to Beneficiary.

### Depositing ETH via Retryables

Currently, the canonical method for depositing ETH into Arbitrum is to create a retryable ticket using the [Inbox.depositEth](./sol_contract_docs/md_docs/arb-bridge-eth/bridge/Inbox.md) method. A Retryable Ticket is created with 0 Callvalue, 0 MaxGas, 0 GasPrice, and empty Calldata. The DepositValue credited to the sender’s account in step 1 simply remains there.

The Retryable Ticket gets put in the retry buffer and can in theory be redeemed, but redeeming is a no-op.

Beyond the superfluous ticket creation, this is suboptimal in that the base submission fee is deducted from the amount deposited, so the user will see a (slight) discrepancy between the amount sent to be deposited and ultimate amount credited in their L2 address. A special message type Taylor-made for ETH deposits that handles them more cleanly will be exposed soon.

### Address Aliasing

When a retryable ticket is executed on L2, the sender's address —i.e., that which is returned by `msg.sender` — will _not_ simply be the address of the contract on L1 that initiated the message; rather it will be the contract's "L2 Alias." A contract address's L2 alias is its value increased by the hex value `0x1111000000000000000000000000000000001111`:

```
L2_Alias = L1_Contract_ Address + 0x1111000000000000000000000000000000001111
```

The Arbitrum protocol's usage of L2 Aliases for L1-to-L2 messages prevents cross-chain exploits that would otherwise be possible if we simply reused L1 contact addresses.

If for some reason you need to compute the L1 address from an L2 alias on chain, you can use our `AddressAliasHelper` library:

```sol
    modifier onlyFromMyL1Contract() override {
        require(AddressAliasHelper.undoL1ToL2Alias(msg.sender) === myL1ContractAddress, "ONLY_COUNTERPART_CONTRACT");
        _;
    }
```

##### Address Aliasing & Refund Addresses In Inbox Methods

Both of the convenience methods `Inbox.depositEth` and `Inbox.createRetryableTicket` include a sanity check to help minimize the risk of user error and ensure refunded Ether on L2 remains accessible. For either method, if the provided `beneficiary` or `credit-back-address` is an L1 contract address, the address will be converted to its address alias, providing a path for the L1 contract to recover the funds. A power-user who understands what they're doing may bypass this conversion by calling `Inbox.createRetryableTicketNoRefundAliasRewrite`.

#### Directly Redeeming / Cancelling Retryables

In the normal, happy case, a retryable ticket is automatically redeemed and executed when it arrives on L2; in this case only a single user-action (publishing the transaction on L1 that creates a retryable ticket) is required. If the transaction is not auto-redeemed (either because no L2 gas was provided or because the L2 retryable ticket reverts for whatever reason), the transaction can now either be redeemed via a signed L2 transaction (probably desireable) or cancelled.

To redeem the retryable, any account can call `ArbRetryableTx.redeem(redemption-txn-id)`. To cancel, the beneficiary address can call `ArbRetryableTx.cancel(redemption-txn-id)`.

See the [ArbRetryableTx](./sol_contract_docs/md_docs/arb-os/arbos/builtin/ArbRetryableTx.md) interface for other related methods, and [arb-ts](https://arb-ts-docs.netlify.app/) for convenience methods around using retryables.

### Demo

See [Greeter](https://github.com/OffchainLabs/arbitrum-tutorials/tree/master/packages/greeter) for a simple demo illustrating the use of retryable tickets.

## Arbitrum to Ethereum

### Explanation

L2 to L1 messages work similar to L1 to L2 messages, but in reverse: an L2 transaction is published with an L1 message as encoded data, to be executed later.

A key difference, however, is that in the L2 to L1 direction, a user must wait for the dispute period to pass between publishing their messages and actually executing it on L1; this is a direct consequence of the security model of Optimistic Rollups (see [finalty](Finality.md).) Additionally, unlike retyable tickets, outgoing messages have no upper bounded timeout; once the dispute window passes, they can be executed at any point. No rush.

### L2 to L1 Messages Lifecycle

The lifecycle of sending a message from layer 2 to layer 1 can be broken down into roughly 4 steps, only 2 which (at most!) require the end user to publish transactions.

**1. Publish L2 to L1 transaction (Arbitrum transaction)**

A client initiates the process by publishing a message on L2 via `ArbSys.sendTxToL1`.

**2. Outbox entry gets created**

After the Arbitrum chain advances some set amount of time, ArbOS gathers all outgoing messages, Merklizes them, and publishes the root as an OutboxEntry in the chain's outbox. Note that this happens "automatically"; i.e., it requires no additional action from the user.

**3. Client gets Merkle proof of outgoing message**

After the Outbox entry is published on the L1 chain, the user (or anybody) can compute the Merkle proof of inclusion of their outgoing message. They do this by calling `NodeInterface.lookupMessageBatchProof`:

```sol

/** @title Interface for providing Outbox proof data
 *  @notice This contract doesn't exist on-chain. Instead it is a virtual interface accessible at 0x00000000000000000000000000000000000000C8
 * This is a cute trick to allow an Arbitrum node to provide data without us having to implement an additional RPC )
 */

interface NodeInterface {
    /**
    * @notice Returns the proof necessary to redeem a message
    * @param batchNum index of outbox entry (i.e., outgoing messages Merkle root) in array of outbox entries
    * @param index index of outgoing message in outbox entry
    * @return (
        * proof: Merkle proof of message inclusion in outbox entry
        * path: Index of message in outbox entry
        * l2Sender: sender if original message (i.e., caller of ArbSys.sendTxToL1)
        * l1Dest: destination address for L1 contract call
        * l2Block l2 block number at which sendTxToL1 call was made
        * l1Block l1 block number at which sendTxToL1 call was made
        * timestamp l2 Timestamp at which sendTxToL1 call was made
        * amouunt value in L1 message in wei
        * calldataForL1 abi-encoded L1 message data
        *
    */
    function lookupMessageBatchProof(uint256 batchNum, uint64 index)
        external
        view
        returns (
            bytes32[] memory proof,
            uint256 path,
            address l2Sender,
            address l1Dest,
            uint256 l2Block,
            uint256 l1Block,
            uint256 timestamp,
            uint256 amount,
            bytes memory calldataForL1
        );
}

```

**4. The user executes the L1 message (Ethereum Transaction)**

Anytime after the dispute window passes, any user can execute the L1 message by calling Outbox.executeTransaction; if it reverts, it can be re-executed any number of times and with no upper time-bound:

```sol
 /**
    * @notice Executes a messages in an Outbox entry. Reverts if dispute period hasn't expired and
    * @param outboxIndex Index of OutboxEntry in outboxes array
    * @param proof Merkle proof of message inclusion in outbox entry
    * @param index Index of message in outbox entry
    * @param l2Sender sender if original message (i.e., caller of ArbSys.sendTxToL1)
    * @param destAddr destination address for L1 contract call
    * @param l2Block l2 block number at which sendTxToL1 call was made
    * @param l1Block l1 block number at which sendTxToL1 call was made
    * @param l2Timestamp l2 Timestamp at which sendTxToL1 call was made
    * @param amount value in L1 message in wei
    * @param calldataForL1 abi-encoded L1 message data
     */
    function executeTransaction(
        uint256 outboxIndex,
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address destAddr,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 amount,
        bytes calldata calldataForL1
    )
```

### Demo

See [outbox-execute](https://github.com/OffchainLabs/arbitrum-tutorials/tree/master/packages/outbox-execute) for client side interactions with the outbox using the [arb-ts](https://arb-ts-docs.netlify.app/) library.

See also [integration tests](https://github.com/OffchainLabs/arbitrum/tree/master/packages/arb-ts/integration_test) and our [Token Bridge UI](https://github.com/OffchainLabs/arb-token-bridge).
