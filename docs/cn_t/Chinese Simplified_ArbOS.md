---
id: ArbOS
title:
  ArbOS: The Arbitrum Operating System
sidebar_label: ArbOS
---

# ArbOS

ArbOS is a trusted "operating system” at Layer 2 that isolates untrusted contracts from each other, tracks and limits their resource usage, and manages the economic model that collects fees from users to fund the operation of a chain's validators. Much of the work that would otherwise have to be done expensively at Layer 1 is instead by ArbOS, trustlessly performing these functions at the speed and low cost of Layer 2.

在L2可信的软件中支持这些功能，而非将其构建在L1强加的以太坊式的架构上，对节省成本有重大意义，因为我们不在L1 EthBridge合约中管理这些资源，而是将其放入了计算和存储更便宜的L2上。 在L2构建一套可信赖的操作系统同样对灵活性有重大意义，因为L2与L1强制的VM架构相比，其代码更容易迭代也更容易定制。

The use of a Layer 2 trusted operating system does require some support in the architecture, for example to allow the OS to limit and track resource usage by contracts

客户端、EthBridge和ArbOS之间通信所用的消息格式的详细规范，请参见ArbOS消息格式规范。
