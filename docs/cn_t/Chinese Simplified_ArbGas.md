---
id: ArbGas
title: ArbGas and running time in Arbitrum
sidebar_label: ArbGas and Runtime
---

ArbGas是Arbitrum用来管理链上执行成本的。 与以太坊gas的理念一致，每个AVM指令都会有一定数量的ArbGas消耗，而一次运算的总成本是该运算包含的指令的ArbGas的加总。

ArbGas并不能直接与以太坊gas相比。 Arbitrum does not have a hard ArbGas limit, and in general an Arbitrum chain can consume many more ArbGas units per second of computation, compared to the number of Ethereum gas units in Ethereum's gas limit. 开发者和用户应该把ArbGas理解为是比以太坊gas更加丰饶且便宜的。

In the eventual production deployment of Arbitrum, a chain will be allowed to charge users a fee for ArbGas, to compensate the chain's validators for their expenses. However, the fee is set to zero by default in Arbitrum beta, for the convenience of developers and users.

## 为什么选择 ArbGas？

One of the design principles of the Arbitrum Virtual Machine (AVM) is that every instruction should take a predictable time to emulate, prove, and proof-check. As a corollary, we want a way to count or estimate the time required to emulate any computation.

有两个原因。 第一，我们需要确保证据检验有可预测的成本，这样就能预测EthBridge需要多少L1 gas，以确保EthBridge不会接近L1的gas limit。

Second, emulation time estimation is important for throughput of a rollup chain, because it allows us to set the chain's speed limit safely.

## ArbGas in assertions

Every assertion includes the amount of ArbGas used by the computation. Like everything else in the assertion, this value is only a claim made by the asserter, and the assertion will be defeatable in a challenge if the claim is wrong.

Although the ArbGas value in an assertion might not be correct, it can be used reliably as a limit on how much computation is required to check the assertion. This is true because a validator who is checking the assertion can cut off their emulation after that much ArbGas has been consumed, because if that much ArbGas has been consumed without reaching the end of the assertion, then the assertion must be wrong and the checker can safely challenge it. For this reason, the AVM protocol can safely use the ArbGas claim in an assertion as an upper bound on the time required to check the assertion's correctness.

An assertion can safely be challenged even if the ArbGas usage is the only aspect of the assertion that is false. When an assertion is bisected, the sub-assertions will include (claimed) ArbGas usages, which must sum to the ArbGas usage of the parent assertion. It follows that if the parent's ArbGas claim is false, at least one of the sub-assertions must make a false ArbGas claim. So a challenger who knows that the parent's ArbGas claim is false will always be able to find a sub-assertion that has a false ArbGas claim.

Eventually bisection will get down to a single AVM instruction, with a claim about that instruction's ArbGas usage. One-step proof verification checks that this claim is correct. So a false ArbGas claim can be pursued all the way down to a single instruction with a false ArbGas claim that will be detected by the one-step proof verification in the EthBridge.

## AVM中的ArbGas计量

The AVM architecture also does ArbGas accounting internally. There is a machine register called `ArbGasRemaining`, which is a 256-bit unsigned integer that behaves as follows.

- The register is initially set to MaxInt256.
- When any instruction executes, that instruction's ArbGas cost is subtracted from the register. If this would make the register's value less than zero, an error is generated and the register's value is set to MaxInt256. （在AVM规范中说明了该错误会导致的控制权转移。）
- 有一条特殊指令可以读取该寄存器的值。
- 还有一条特殊指令可以将该寄存器的值设置为任意值。

This mechanism allows the trusted AVM runtime to control and account for the ArbGas usage of applicaton code. The runtime can limit an application call's use of ArbGas to N units by setting the register to N before calling the application, then catching the out-of-ArbGas error if it is generated. At the beginning of the runtime's error-handler, the runtime would read the ArbGasRemaining register, then set the register to MaxInt256 to ensure that the error-handler could not run out of ArbGas. 如果读取寄存器的值接近于MaxInt256，那么一定是应用程序产生了Out-of-ArbGas错误。 （可能是应用程序生成了一个不同的错误，而仍有少量 ArbGas，然后在错误处理程序的最开始出现一个 out-of-ArbGas 错误。 In this case, the second error would set the ArbGasRemaining to MaxInt256 and throw control back to the beginning of the error-handler, causing the error-handler to conclude that an out-of-ArbGas error was caused by the application. 我们认为这种合理的行为是正确的。）

If the application code returns control to the runtime without generating an out-of-ArbGas error, the runtime can read the ArbGasRemaining register and subtract to determine how much ArbGas the application call used. 并充值进程序的账户中。

运行时可以安全地忽略掉ArbGas计量机制。 如果没有使用过特殊指令，寄存器会被设置为MaxInt256，其值会减少但实践中不可能到0，所以不会有错误产生。

One caveat on this approach is that the application must be prevented from using the special instruction that modifies the ArbGasRemaining register. The compiler should not emit that instruction when compiling application code, and the AVM loader and runtime must scan application code before loading it, to make that that this AVM instruction (and other instructions treated as privileged) do not occur in the application code.

## 速度上限

The security of Arbitrum chains depends on the assumption that when one validator makes an assertion, other validators will check it and issue a challenge if it is wrong. This requires that the other validators have the time and resources to check each assertion in time to issue a timely challenge. The Arbitrum protocol takes this into account in setting deadlines for assertions.

这就给AVM的运行设置了实际的速度上限：长远来看VM不可能运行地比验证者检验速度还要快。 If assertions are published at a rate faster than the speed limit, their deadlines will get farther and farther in the future. Due to the limit on how far in the future a deadline can be, this will eventually cause new assertions to be slowed down, thereby enforcing the effective speed limit.

Being able to set the speed limit accurately depends on being able to estimate the time required to emulate an AVM computation with some accuracy. Any uncertainty in estimating emulation time will force us to set the speed limit lower, to be safe. 而我们确实不想把速度上限设低，所以会尝试精确的估算。

## ArbGas

ArbGas is a measure of how long it takes for a validator to emulate execution of an AVM computation. This is scaled so that 100 million ArbGas is approximately equal to 1 second of CPU time on the Offchain Labs developer laptops in early 2020.

ArbGas differs from Ethereum gas, because ArbGas tries to estimate emulation on AVM, whereas Ethereum gas plays a similar role on Ethereum, which has different costs and tradeoffs. (For example, accesses to storage are very expensive on Ethereum because a storage write in Ethereum creates an obligation for every Ethereum miner, potentially for all future time.)

ArbGas costs of each AVM instruction are set by measurement.

## Maintaining the constant cost invariant

Making every instruction require constant cost to emulate, prove and proof-check is easy for most instructions. The challenging case is access to memory.

To this end, the AVM uses an unusual structure: fixed-size immutable tuples. A tuple is a sequence of up to eight slots, each containing an Arbitrum value. The contained values may themselves be tuples, so that one tuple can represent an arbitrarily large tree of values. (In practice it may be represented as a DAG, but the difference does not matter because tuples and their contents are immutable.)

Using this structure, a large array or memory can be represented as a tuple-tree. Essentially this is taking the Merkle tree structure that is common in implementations of systems like this, and making it explicit. There is no loss of asymptotic efficiency: access to such a structure requires a logarithmic number of AVM instructions, but each of those instructions take constant time, so access to a Merkleized memory takes logarithmic time in total. The Arbitrum standard library provides facilities to support such structures.

To support constant-time proving, each tuple contains a hash of its contents, which is computed from the hashes of each slot's contents, in the usual Merkle tree manner. This hash can be computed when the tuple is created. Because tuples are immutable, this needs to happen only once--once a tuple exists its hash cannot change.

This hashing strategy makes one-step proofs require constant time and space to create and check, because a one-step proof of an instruction involving tuples need only check that the hash of a tuple is consistent with the hashes of its slot contents.

## Lazy hashing and amortized constant time

To improve performance, we relaxed the constant-time requirement to require only constant amortized time, within the emulation of each individual assertion. In other words, each instruction gets an ArbGas charge, but part of the ArbGas charge assigned to an instruction can be unused at the time of the instruction's emulation but instead "saved for later". Then later--but still within the emulation of the same assertion--the saved ArbGas can be used to do additional work.

This use of amortization within a single assertion is safe because deadlines and speed limits apply only to assertions as a whole, so moving time costs around with in a single assertion does not affect the ability to meet deadlines or speed limits.

Currently the only use of amortization is lazy hashing of tuples. When a tuple is created, the AVM emulator doesn't compute its hash but instead marks it as "hash pending". Sufficient ArbGas to compute the tuple's hash is saved from the instruction that creates the tuple. The tuple's hash will be computed when it is needed--either because the AVM `hash` instruction is executed on it, or because its hash is needed as part of an assertion.

Lazy hashing saves computation because some tuples will be discarded before their hash is ever needed. So we save the cost of hashing those discarded tuples--which are very common in programs transpiled from Ethereum, because Ethereum transactions use ephemeral memory during a transaction and retain only a small amount of storage between transactions.

If a tuple is not discarded during an assertion, it will need to be hashed in order to compute the AVM hash when the current assertion ends. The AVM hash is a Merkle-type hash that covers all reachable tuples, so computation of the AVM hash will force hashing of all reachable tuples. The cost of hashing each such tuple will be covered by ArbGas saved when that tuple was created.

Note that because each assertion forces hashing of all reachable tuples, an assertion will never leave behind an "unfunded liability" that later assertions must pay back. So every hashing that is done is covered by an earlier ArbGas charge within the same assertion.
