---
id: AVM_Design
title: AVM design rationale
sidebar_label: AVM design rationale
---

This document outlines the design rationale for the Arbitrum Virtual Machine (AVM) architecture.

AVM设计的出发点是以太坊虚拟机EVM。 Because Arbitrum aims to efficiently execute programs written or compiled for EVM, Arbitrum uses many aspects of EVM unchanged. 例如，AVM采用了EVM的基础整型数据结构（256位大端序无符号整数，uint256），以及EVM中对整型操作的指令。

Differences between AVM and EVM are motivated by the needs of Arbitrum's Layer 2 protocol and Arbitrum's use of a multi-round challenge protocol to resolve disputes.

## 执行vs证明

Arbitrum, unlike EVM and similar architectures, needs to support both execution (advancing the state of a computation by local emulation) and proving (convincing an L1 contract or other trusted party that a claim about execution is correct). EVM-based systems resolve disputes by re-executing the disputed code, whereas Arbitrum relies on a challenge protocol that leads to an eventual proof.

We want execution to be optimized for speed in a local, trusted environment, because local execution is the common case. Proving, on the other hand, will be needed less often but must still be efficient enough to be viable even in a congested L1 system. The system will rarely need to prove, but it always needs to be _prepared_ to prove. 这种执行和证明分离设计在正常情况下，极大地提高了执行的效率。

## ArbOS

Another difference in requirements is that Arbitrum uses ArbOS, a "operating system" that runs at Layer 2. ArbOS控制着合约的执行，将各个合约彼此分隔，并追踪它们的资源使用情况。

在L2可信的软件中支持这些功能，而非将其构建在L1强加的以太坊式的架构上，对节省成本有重大意义，因为我们不在L1 EthBridge合约中管理这些资源，而是将其放入了计算和存储更便宜的L2上。 在L2构建一套可信赖的操作系统同样对灵活性有重大意义，因为L2与L1强制的VM架构相比，其代码更容易迭代也更容易定制。

使用L2可信赖的操作系统确实需要有VM指令集的支持，例如，允许OS限制并追踪合约使用的资源。

## 支持梅克尔化

Any Layer 2 protocol that relies on assertions and dispute resolution (which includes at least all rollup protocols) must define a rule for Merkle-hashing the full state of the virtual machine. That rule must be part of the architecture definition because it is relied upon in resolving disputes.

It must also be reasonably efficient to maintain the Merkle hash and/or recompute it when needed. 这些事情关系到架构如何构建其内存。 Any storage structure that is large and mutable will be relatively expensive to Merkleize, and an algorithm for Merkleizing it must be part of the architecture specification.

AVM对此的解决方案是，构建一种大小有限、不可更改的内存对象（元组，Tuples），通过引用来囊括其他元组。 元组虽然不可原地改变，但有一个指令可以复制一个元组并对其进行修改。 如此便能够构建大平面的树状内存结构。 应用程序通过内部使用元组的库就能够使用一些诸如大平面数组，key-value存储，等等特性。

元组的特性令创造首尾循环的元组是不可能的，AVM可以通过引用计数、不可变结构安全地管理元组。 每个元组的哈希只需计算一次，因为元组是不可变的。

## Code organization: Codepoints

传统的代码组织结构会维护一个线性的指令队列，并将进程计数器（PC）指向下一条要执行的指令。 With this conventional approach, proving an instruction of execution requires logarithmic time and space, because a Merkle proof must be presented to prove which instruction is under the current PC.

The AVM uses this conventional approach for execution, but it adds a feature that makes proving and proof-checking require constant time and space. The CodePoint for the instruction at some PC value is the pair (instruction at PC, Hash(CodePoint at PC+1)). 如果没有CodePoint at PC+1，则使用0。

为了进行证明，『进程计数器』被『当前码点哈希』值所代替，该值是VM状态的一部分。 The preimage of this hash will contain the current instruction, and the hash of the following codepoint, which is everything the verifier needs to verify what the instruction is and what the current CodePoint hash value will be after the instruction, if the instruction isn't a Jump.

所有的JUMP指令的目的地都是码点，因此，一个JUMP指令执行的证明也是信手拈来的，不仅有JUMP后的进程计数器，还有『当前码点哈希』这个寄存器在JUMP执行后的值。 在任何情况下，证明和验证都只需要常量时空。

在一般的执行中（此时不需要证明），会按照传统架构使用进程计数器。 However, when a proof is needed, the prover can use a lookup table to get the CodePoint hashes corresponding to any relevant PCs.

## Support for ArbOS

ArbOS, running at Layer 2, isolates untrusted programs from each other, tracks and limits their resource usage, and manages the economic model that collects fees from users to fund the operation of a chain's validators.

In support of this, the AVM includes instructions to support saving and restoring the machine's stack, managing machine registers that track resource usage, and receives messages from external callers. 这些指令是ArbOS自身使用的，不过ArbOS能够确保它们不会出现在不受信任的代码中。
