---
id: Inside_Arbitrum
title: Inside Arbitrum
sidebar_label: Inside Arbitrum
---

本章节是对 Arbitrum 的设计及其原理的深入解析。 本文不是 API 文档，也不是代码开发教程，如有需要请查看其余文章。 “Inside Arbitrum”适合于想要了解 Arbitrum 设计的兴趣者。

## 为什么使用Arbitrum?

Arbitrum是以太坊的L2扩容方案，它拥有独特的特性集：

- 无需信任的安全性：安全扎根于以太坊，任何人都可以确保正确的L2结果
- 以太坊兼容性：所有EVM标准的合约和转账都可以在Arbitrum上执行
- 可扩展性：将以太坊的计算和存储转移至链下，吞吐量更高
- 最低成本：为最小化以太坊L1燃气成本而生，降低每笔交易的成本

其余的L2方案也提供了其中一部分特性，但据我们所了解的，并没有一种方案能在相同成本下提供同样的特性集。

## 高屋建瓴

在最基础层，Arbitrum链工作方式如图：

![img](https://lh4.googleusercontent.com/qwf_aYyB1AfX9s-_PQysOmPNtWB164_qA6isj3NhkDnmcro6J75f6MC2_AjlN60lpSkSw6DtZwNfrt13F3E_G8jdvjeWHX8EophDA2oUM0mEpPVeTlMbsjUCMmztEM0WvDpyWZ6R)

用户与合约将信息发送至收件箱。 链将各条信息逐一读取并依次执行。 将链的状态更新并产生一些输出。

若想要Arbitrum链为你执行一笔交易，你需要把该笔交易提交到收件箱中。 随后Arbitrum链会发现这笔交易，然后执行，并产生输出：一笔交易的记录，以及交易所中的任何提款等内容。

交易执行是确定的——这意味着链的状态仅取决于收件箱。 因此，交易的结果在你讲交易提交到收件箱的那一刻就已经是确定的了。 任何一个Arbitrum节点都能告知你结果。 （如果你喜欢也可以自己运行一个节点。）

本文档中的所有的技术细节都与这个模型有关。 从此模型谈起直到Arbitrum的完整论述，我们需要回答如下问题：

- 谁负责追踪收件箱、链状态、输出？
- Arbitrum如何确保链状态和输出是正确的？
- 以太坊用户、合约如何与Arbitrum互动？
- Arbitrum是如何支持兼容以太坊的合约与转账的？
- 以太坊币和代币是如何转入转出Arbitrum链的？在Arbitrum链上是如何对其进行管理的？
- 如何运行我自己的Arbitrum节点或成为一个验证者？

## 乐观式Rollup

Arbitrum是一种乐观式Rollup。 我们来解读一下这个词汇。

_Rollup_

仲裁是一个渐进过程。 这意味着输入链的信息——输入收件箱的信息——都作为通话数据记录在以太坊链上。 正因为如此，所有人都有确定链当前正确状态所需的信息——他们拥有收件箱的全部历史，且收件箱历史独特地决定了结果， 如果需要，它们只能在公共信息基础上重建这一链的状态。

这也使得任何人都能够充分参与Arbitrum议定书，运行一个Arbitrum中心或作为一个验证者参加。 任何关于Arbitrum链历史或状态的信息都不是秘密。

_乐观式_

Arbitrum是乐观的，通过验证者发布rollup区块以及任何人都可以对其进行挑战的方式，Arbitrum将链状态不断向前推进。 如果挑战期（大约为一周）结束后仍没有对rollup区块提出挑战，Arbitrum就会将该rollup区块认定为正确的。 如果在挑战期内有人提出挑战，Arbitrum会使用一个高效率的争议解决协议（下述）来判定谁是作恶者。 作恶者的质押资金将被没收，其中一部分将奖励给诚信者（另一部分被销毁，以保证即使有共谋发生作恶者仍会被惩罚）。

因为试图作弊的一方会损失押金，所以作弊地尝试应该是非常罕见的，正常情况下是验证者发布正确的rollup区块，没有人去质疑它。

## 交互式证明

在乐观式rollup中，最重要的设计是如何解决争议。 假设Alice断言链上会产生某个特定结果，而Bob不认同。 那么仲裁协议应该接受谁的提议呢？

基本上，有两种方案：交互式证明、再执行交易。 Arbitrum使用交互式证明，我们相信这种方式是更有效率更灵活的。 大部分Arbitrum的设计都遵循此观点。

### 交互式证明

在交互式证明的范式中，Alice和Bob会在一个往返驳诘式的协议中进行交互，以最大限度减少L1上仲裁人所需要的工作量。

Arbitrum的解决方案是基于争议的分解。 如果Alice的断言包含的行为有N步，Alice会将其分解为两个N/2长度的断言，Bob则需要选择N/2步长度的断言来挑战。 现在争议的规模减半。 该过程不断继续，每次将争议范围减半，直到找到它们所争议的那一步行为。 请注意，到目前为止L1裁判还不需要考虑争议的是非曲直。 L1仲裁在范围缩窄到单步时才会介入，去检查该行为到底做了什么以及Alice的断言是否正确。

交互式证明的核心思想是，若Alice和Bob产生争议，应该尽可能将大部分工作量置于链下解决，而不是把所有工作量都放到L1的仲裁合约上。

### 再执行交易

交互式证明的替代方案是让每一个rollup区块中在每一条交易执行后都更新一个断言状态哈希。 在有争议的情况下，L1裁判会对整个交易进行审查，来确定是否满足Alice的断言。

### 为什么交互式证明更好

基于下列理由，我们坚定认为交互式证明是更好的选择。

*在乐观式情况下更加有效率：*由于交互式证明能够解决多于一笔的争议，它能够让rollup区块只包含一个所有行为执行完毕后的末状态哈希。 相反，再执行则需要在rollup区块中为每一笔交易都附上一个状态声明。 在一个rollup区块中有成千上百笔交易，所以在L1燃气经济性上有显著不同——而L1燃气则是成本的主要来源。

*在悲观式情况下更加有效率：*在有争议情况下，交互式证明需要L1仲裁合约只需要检查Alice和Bob的切分步骤行为是正确的，例如Alice确实将自己的断言二等分了。 （在接触到最终步骤之前，仲裁并不需要判定Alice的断言是否正确，Bob在链下做了这个工作。） 只有一步交易需要再执行。 相反，再执行交易范式则需要L1仲裁去评估整个的交易历史。

*每笔交易更高的gas limit：*交互式证明可以摆脱以太坊每笔交易的比较紧张的gas limit；一笔需要花费大量gas的交易在以太坊上无法实现，但在Arbitrum上却是有可能的。 显然，gas limit不可能是无限的，但还是可以比以太坊上大很多。 考虑到以太坊的话，在Arbitrum上高gas交易的尾翼缺点是，可能需要稍多一点的交互式证明步骤（而且还是在存在欺诈的情况下）。 而对于再执行交易范式，其gas limit必须低于以太坊，因为那样才有可能对在单笔以太坊交易中对其包含的所有交易的执行进行检查（比直接执行交易更贵）。

*合约大小不受限制：*交互式证明不需要为每一个L2合约部署一个对应的以太坊合约，所以也不需要遵循以太坊所规定的合约大小限制。 只要有Arbitrum的可仲裁机制，在L2 上部署一个合约就与进行其他计算是一样的。 相反，再执行交易范式需要币以太坊更小的合约大小限制，因为他们需要检验该合约，而能够检验该合约的代码则必须能装进以太坊合约中。

*更多实现上的灵活性：*交互式证明提供了实现上更多的灵活性。例如，增加EVM中没有的指令。 而这仅需要通过在以太坊上验证一个单步证明即可。 相反，再执行交易范式则要受限于EVM。

### 交互式证明驱动着Arbitrum的设计

Arbitrum的许多设计都是由交互式证明所带来的可能所驱动的。 如果你看到一些Arbitrum的特性并疑惑为什么会这样，那么请记住两个非常好的问题：“这个特性是怎样支持交互式证明的？”和“它是怎样利用交互式证明的？” 你在Arbitrum中大部分的问题都与交互式证明相关。

## Arbitrum架构

下图展示了Arbitrum的基础架构。

![img](https://lh5.googleusercontent.com/1qwGMCrLQjJMv9zhWIUYkQXoDR2IksU5IzcSUPNJ5pWkY81pCvr7WkTf4-sb41cVohcnL-i6y8M1LU8v-4RXT_fdOsaMuLXnjwerSuKTQdHE-Hrvf4qBhRQ2r7qjxuAi3mk3hgkh)

左侧是用户以及用户选择的连接到区块链的服务提供者。 右侧是构建于以太坊之上的Arbitrum系统。

我们先讲一讲右侧的Arbitrum栈是如何工作的，然后再来讲一讲当左边用户连接到它时发生了什么。

最下面是我们的老朋友以太坊。 Arbitrum构建于以太坊之上并继承了其安全性。

在以太坊之上是ETHBridge，它由管理Arbitrum链的一系列以太坊上的合约组成。 EthBridge仲裁Arbitrum rollup协议，以保证L2运行的正确性。 （更多关于rollup协议请见下方的Rollup协议分区。） EthBridge还维护着链的收件箱和发件箱，让用户与合约能够将交易信息提交给L2并观察这些交易的输出。 用户，L1合约，Arbitrum节点，调用EthBridge的一系列合约来与Arbitrum链交互。

EthBridge上方的水平线是AVM，EthBridge就是通过这里与上层交流的。AVM可以执行程序来读取输入并产生输出。 这里是Arbitrum最重要的接口，因为它区分开了L1和L2——具体分为抽象为收件箱/执行/发件箱/L1与使用该抽象模型的L2.

![img](https://lh4.googleusercontent.com/qwf_aYyB1AfX9s-_PQysOmPNtWB164_qA6isj3NhkDnmcro6J75f6MC2_AjlN60lpSkSw6DtZwNfrt13F3E_G8jdvjeWHX8EophDA2oUM0mEpPVeTlMbsjUCMmztEM0WvDpyWZ6R)

再上一层是ArbOS。 由Offchain Labs开发的软件，负责维护记录，交易管理，以及对智能合约监管。 之所以叫ArbOS是因为它就像电脑或手机的操作系统（轻量级的）一样，它先启动然后再管理链上的其他代码。 重要的一点是，ArbOS运行于L2上而非以太坊上，所以非常好地利用了扩容和L2低成本的运算。

ArbOS之上的水平层叫做EVM兼容层，因为ArbOS为智能合约提供了兼容以太坊虚拟机的执行环境。 也就是说，你可以向ArbOS发送合约的EVM代码，像在以太坊上部署合约一样，ArbOS会加载合约并令其可用。 ArbOS在兼容性的细节方面处理的非常好，所以智能合约开发者可以像在以太坊上那样编写代码（更常见的情况是，直接将现有的以太坊合约移植过来）。

在整个栈智之上，图表的右上部分，是由开发者部署到Arbitrum上的EVM合约。

图表右边是整个Arbitrum链的功能。 现在我们再来看一下左侧，左侧更多与用户有关。

左下方是标准的以太坊节点，用户借此与以太坊链交互。 上面的是Arbitrum节点。 顾名思义，是用于用户与Arbitrum交互的。 Arbitrum节点支持与以太坊节点相同的API，所以与现行的以太坊工具都能完美工作——你可以将你的以太坊钱包或工具直接指向Arbitrum节点，双方即可通信了。 正如在以太坊上一样，任何人都可以运行Arbitrum节点，但仍会有许多人选择依赖其他人建立的节点。

一些 Arbitrum 节点为用户请求提供服务，而另一些则选择仅充当验证者，以确保 Arbitrum 链的正确性。 （有关详细信息，请参阅 [验证者](#validators) 部分。）

最后但同样重要的是，我们在左上角看到 **用户**。 用户使用钱包、dapp 或其他工具与 Arbitrum 进行交互。 由于 Arbitrum 节点支持与以太坊相同的 API，因此用户不需要全新的工具，开发人员也不需要重写他们的 dapp。

## 在线上方还是下方？

我们常说，在Arbitrum架构中分割L1和L2的是位于AVM的这条线。 这种分层有利于界定某些行为发生的地点。

![img](https://lh5.googleusercontent.com/1qwGMCrLQjJMv9zhWIUYkQXoDR2IksU5IzcSUPNJ5pWkY81pCvr7WkTf4-sb41cVohcnL-i6y8M1LU8v-4RXT_fdOsaMuLXnjwerSuKTQdHE-Hrvf4qBhRQ2r7qjxuAi3mk3hgkh)

线下方，是用来确保AVM以及链的执行的正确性的。 而线上方则假设AVM会正确运行，专注于与运行在L2上的软件的互动。

例如，Arbitrum验证者在下方工作，因为他们参与由线下方EthBridge管理的rollup协议，来确保AVM的运转是正常的。

另一边，Arbitrum全节点工作在线上方，它们每个节点在本地都有一份AVM状态的副本，并假设线下方的工作机制能够保证每个人本地的运算最终都相同。它们并不监视下方是如何工作的。

大部分用户在大部分场景下，只关心线上方的事。 与Arbitrum互动与其他链互动是相同的，不需要考虑线下方如何确保链工作正常。

## The EthBridge

EthBridge是管理Arbitrum链的一组合约。 EthBridge会记录收件箱的内容，链状态的哈希，以及输出信息。 EthBridge是Arbitrum链上发生了什么的终极权威消息源。

EthBridge是Arbitrum安全的基石。 它运行于以太坊上，所以是公开透明且无需信任的。

收件箱合约则管理着收件箱。 收件箱记录了每条消息的哈希。 调用一个send*函数会向Arbitrum的收件箱发送一条信息。

收件箱合约确保进入的信息是准确无误的：信息需要正确记录发送人，以太坊区块编号，时间戳。

理所当然地，还有一个发件箱合约，管理着链的输出。例如，在Arbitrum上发生的需要（最终会）返回在以太坊上的事（比如提现）。 当一个rollup区块确认后，该区块的输出就放入了收件箱内。 [桥接](#bridging)部分详细介绍了输出最终如何反映在以太坊上。

Rollup合约及其伙伴管理着整个rollup合约。 它们共同追踪Arbitrum链的状态：提出的，接受的，被拒绝的rollup区块以及在哪个rollup结点上谁进行了质押。 Challenge挑战合约及其伙伴则负责解决验证者之间的哪个rollup区块是正确的的争端。 Rollup，Challenge和它们的朋友们会在Rollup协议章节中详细介绍。

## Arbitrum Rollup协议

在深入理解rollup协议之前，有两件事需要明确。

首先，_如果你是Arbitrum的用户或开发者，你不需要理解rollup协议。_ 除非你认为有必要，否则你都不需要对其进行思考。 这就像火车乘客与火车引擎一样：乘客知道引擎的存在，只需要引擎正常工作即可，但并不需要花费时间监控它或学习其内部结构。

我们欢迎大家来学习，观察，甚至参与到rollup协议中，不过对大部分人来说这并非必要的。 如果你只是一位传统的火车乘客，可以直接跳到[验证者章节](#validators)。 如果不是则请继续阅读。

其次，需要指出，*rollup协议并不决定交易的结果，它只对结果进行确认*。 结果是由收件箱中信息的顺序确定的。 所以，一旦消息进入了收件箱，其结果就是确定的——Arbitrum节点会将待完成的交易提交。 就Arbitrum用户而言Rollup协议的作用是用来确认这些结果。 （这也是为什么Arbitrum用户可以不关心rollup协议。）

您可能想知道我们为什么需要rollup协议。 如果每个人都知道交易的结果，为什么还要rollup协议确认呢？ 两个原因。 首先，有人可能会撒谎、作弊，所以需要一个权威的、无需信任的方式来分辨谁是恶意的。 第二，以太坊并不知道这些结果。 而L2扩容的核心要义就是以太坊不需要承担交易的所有工作量，Arbitrum交易速度非常快，以太坊是没有能力去监控每一笔Arbitrum交易的。 但一旦结果确认了，以太坊就知晓了，结果就是可信赖的。

有了这些铺垫，我们就可以深入rollup协议的细节了。

参与rollup协议的人成为_验证者_， 任何人都可以成为验证者。 有些验证者则会选择成为质押者——将以太质押进来，如果作弊将被罚没。 这些都做都是免许可的：任何人都可以成为验证者或质押者。

Rollup协议的核心安全属性是_AnyTrust Guarantee_（“一诚则成”原理）：只要有一个诚实的验证者，那么整个链的正确运行就会有绝对的保证。 这意味着Arbitrum链的运行是与以太坊一样免信任的。 You, and you alone (or someone you hire) can force your transactions to be processed correctly. And that is true no matter how many malicious people are trying to stop you.

### Rollup链

Rollup协议记录了一条rollup区块的链条。 它们与以太坊区块并不是同一个概念。 你可以认为rollup链是一条概念上的单独的链，是由Arbitrum rollup协议管理并监控的。

验证者可以提出rollup区块。 新的rollup区块一开始是_待决状态_。 最终每个rollup区块都会被_解决_，要么被_确认_，要么被_拒绝_。 已确认的区块构成了整条链的历史。

每个rollup区块包含：

- rollup区块编号
- 父rollup区块编号：本rollup区块之前一个（被宣称为）正确的rollup区块的编号
- 本链历史上所发生的运算量（以ArbGas计量）
- 本链历史上所接收的收件箱信息数量
- 对本链历史输出的哈希
- AVM 状态的哈希值。

除了rollup区块编号，上述内容中的其余内容均是区块的提出者声明的。 Arbitrum在最开始并不知道这些内容是否是正确的。 如果所有的内容都正确，rollup协议最终应确认该区块。 如果有任意内容是错误的，该区块最终会被拒绝。

每一个区块都会隐形地声明它的父区块是正确的。 这也连锁式地标明了：一个区块会隐形地宣称整条链是正确的：一系列的祖先区块都是正确的，直至整条链的创始区块。

同样，每个区块都隐形地声明，其兄弟区块（有着同一个父区块的其他区块）都是错误的（如果存在兄区块的话）。 若两个区块是兄弟关系，兄区块是正确的，那么弟区块一定是错误的，即使弟区块中的所有内容是真实有效的。

每个区块都会被分配一个截止时间，在该时间内其他验证者才能对其进行响应。 如果你是一名验证者，并认同某一个rollup区块是正确的，那么你什么也不用做。 如果你不认同该区块，你可以发布另一个有不同结果的区块，你可能会被该区块的质押者挑战。 （更多请见下方挑战章节。）

正常情况下，rollup链看起来是这样的：

![img](https://lh3.googleusercontent.com/vv118kJMXj76PG6J-Jv4BC9KTpe72mdfD1uWoqhKXvKKfPWHW6wMMCvJ9KKQx_VXIw34XfzT4yfyNVtQVstYRczLk6kLKvBv8Pbl-0MjSzGxz1Z_8T5Y_6UcDMWpy7_D9PxQYKdT)

左侧都是已确认区块，代表了该链的早期历史。 这些区块都被EthBridge接受并记录下来。 94号区块是“最新确认区块”。 在右侧，有一系列新的刚被提出的rollup区块。 EthBridge尚不能确认或拒绝，因为其截止时间还没有到。 待决区块中最老的95号区块，被称为“首个待决区块”。

注意，一个待决区块是可以连接在另一个待决区块之后的。 这使得验证者能够不断地提出新的区块而不用等待EthBridge的最终确认。 正常乐观情况下，所有的待决区块都是有效的，最终都会被接受。

下面的例子展现了有恶意验证者存在的情况下链的状态。 这是一个人工策划过的场景，用来说明协议可能碰到的各种情况。我们将各种情况都融汇到了一个场景中去。

![img](https://lh3.googleusercontent.com/IKBNeX9IVAD5Vom8vqYER4CEZhTecJJrp51ddlEGYiZrdV6y9zaG0Ip8HuKgfJ-eS9_TN_C2I0EPl-7H5ITRgSQqJONnSE7X0P62sRbGoiv_shmijBxsVDJL9RhWbyDjs2lKxU-M)

看起来有些复杂，我们梳理下：

- 区块100已被确认。
- 区块101宣称自己是区块100的正确子区块，但101被拒绝了（因为打了叉）。
- 区块102最终被确认为区块100的正确子区块。
- 区块103也确认了，现在是最新确认区块。
- 区块104是103的子区块，105是104的子区块。 由于104是错误的，105自然也会被拒绝，因为它的父区块就是错的。
- 区块106待决。 它宣称自己是区块103的子区块，但协议尚未决定是确认还是拒绝它。 这是首个待决区块。
- 区块107和108延续自区块106， 它们也是待决状态。 如果106被拒绝，它们也会被拒绝。
- 区块109不认同区块106，因为它们的父区块相同。 它们中至少会有一个被拒绝，但协议尚未解决。
- 区块110跟随109。 待决状态。 如果109被拒绝，110也会。
- 区块111跟随105。 111最终肯定会被拒绝因为其父区块已经被拒绝， 但它还没有被拒绝，因为协议按照块号顺序解析块，所以协议必须按顺序解析 106 到 110，然后才能解析 111。 在110解决后，111会被立即拒绝。

再次提醒：这种情况在实践中是非常不可能发生的。 本图中，至少有四方质押在了错误的结点上，尘埃落定后至少会有四方失去质押物。 协议是有能力正确处理这些情况的，但这确实是边缘场景。 这个例子仅用来说明原理上可能会出现的各种情况，以及协议会如何处理。

### 质押

在任何时间，都会有一部分验证者成为质押者，而另一部分则不会。 质押者通过EthBridge充值资金，如果输掉挑战则会被没收。 目前所有链接受以太币为质押物。

单笔质押可覆盖一系列rollup区块。 每个质押者都质押在最新确认区块上；如果你质押了一个区块，你还可以继续向其子区块质押。 所以你是可以质押在一串连续正确的区块上的。 一个质押就足以让你参与该区块序列。

要创建新的rollup区块，你必须成为质押者，并且已经在你所创建的区块的父区块上质押了资金。 创建新区块的质押需求确保了如果作恶则惩罚机制能够执行。

EthBridge记录了当前所需要的质押数量。 正常情况下会与基础质押数量相等，基础质押数量是Arbitrum链的一个参数。 但如果链后来行动迟缓，质押数量会增加，下面为详述。

质押规则：

- 如果你没有质押，可以质押在最新已确认rollup区块上。 质押数量由EthBridge的当前最小质押额确定。
- 如果你已经质押在了一个rollup区块上，你还可以将质押物移动到任意的子区块上。 （EthBridge会追踪你所质押的区块的最大高度，并允许你为任意子区块质押，同时更新最大高度至该子区块。） 这个过程不需要额外增加质押。
  - 只有一个特殊情况需要额外增加质押物，即在你质押的区块下创建新的rollup区块。
- 如果你仅仅质押在了最新确认区块（可能是比较老的区块）上，你或任何人都可以请求将你的质押物返还。 质押物返还给你后，你将不再质押者。
- 如果你输掉了挑战，你的质押物将从所有的区块上移除，没收为罚金。

请注意，一旦你质押了一个rollup区块，是无法撤销质押的。 你对这个区块就做出了承诺。 最终会发生两件事：该区块确认了，或者你的质押被没收了。 只有在区块被确认后你才能拿回你的质押物。

#### 设置当前最小质押额

之前没有讨论当前最小质押额是如何设定的。 通常，它等于基础质押额，基础质押额是Arbitrum链的一个参数。 不过，如果链确认区块的速度缓慢，质押数量会暂时增加。 具体来说，最小质押额 = 基础质押额 × 一个因子，该因子与自首个待决区块的截止时间以来所流逝的时间呈指数增长。 这样可以确保，如果有作恶者通过错误质押来降低链的运行速度（尽管最终会被没收），它们的降速攻击也需要付出指数增长的成本。 随着区块确认继续向前，质押需求最终会回到正常。

### 确认或拒绝rollup区块的规则

解决rollup区块的规则非常简单。

首个待决区块满足下列情况会被确认：

- the block’s predecessor is the latest confirmed block, and
- the block’s deadline has passed, and
- there is at least one staker, and
- all stakers are staked on the block.

The first unresolved block can be rejected if:

- the block’s predecessor has been rejected, or
- all of the following are true:
  - the block’s deadline has passed, and
  - there is at least one staker, and
  - no staker is staked on the block.

A consequence of these rules is that once the first unresolved block’s deadline has passed (and assuming there is at least one staker staked on something other than the latest confirmed block), the only way the block can be unresolvable is if at least one staker is staked on it and at least one staker is staked on a different block with the same predecessor. If this happens, the two stakers are disagreeing about which block is correct. It’s time for a challenge, to resolve the disagreement.

## Challenges

Suppose the rollup chain looks like this:

![img](https://lh4.googleusercontent.com/kAZY9H73dqcHvboFDby9nrtbYZrbsHCYtE5X9NIZQsvcz58vV0WUWUq1xsYKzYWQSc1nPZ8W86LLX0lD3y-ctEaG2ISa2Wpz2pYxTzW09P1UvqSDuoqkHlGDYLLMTzLqX4rlP8Ca)

Blocks 93 and 95 are sibling blocks (they both have 92 as predecessor). Alice is staked on 93 and Bob is staked on 95.

At this point we know that Alice and Bob disagree about the correctness of block 93, with Alice committed to 93 being correct and Bob committed to 93 being incorrect. (Bob is staked on 95, and 95 claims that 92 is the last correct block before it, which implies that 93 would be incorrect.)

Whenever two stakers are staked on sibling blocks, and neither of those stakers is already in a challenge, anyone can start a challenge between the two. The rollup protocol will record the challenge and referee it, eventually declaring a winner and confiscating the loser’s stake. The loser will be removed as a staker.

The challenge is a game in which Alice and Bob alternate moves, with an Ethereum contract as the referee. Alice, the defender, moves first.

The game will operate in two phases: dissection, followed by one-step proof. Dissection will narrow down the size of the dispute until it is a dispute about just one instruction of execution. Then the one-step proof will determine who is right about that one instruction.

We’ll describe the dissection part of the protocol twice. First, we’ll give a simplified version which is easier to understand but less efficient. Then we’ll describe how the real version differs from the simplified one.

### Dissection Protocol: Simplified Version

Alice is defending the claim that starting with the state in the predecessor block, the state of the Virtual Machine can advance to the state specified in block A. Essentially she is claiming that the Virtual Machine can execute N instructions, and that that execution will consume M inbox messages and transform the hash of outputs from H’ to H.

Alice’s first move requires her to dissect her claims about intermediate states between the beginning (0 instructions executed) and the end (N instructions executed). So we require Alice to divide her claim in half, and post the state at the half-way point, after N/2 instructions have been executed.

Now Alice has effectively bisected her N-step assertion into two (N/2)-step assertions. Bob has to point to one of those two half-size assertions and claim it is wrong.

At this point we’re effectively back in the original situation: Alice having made an assertion that Bob disagrees with. But we have cut the size of the assertion in half, from N to N/2. We can apply the same method again, with Alice bisecting and Bob choosing one of the halves, to reduce the size to N/4. And we can continue bisecting, so that after a logarithmic number of rounds Alice and Bob will be disagreeing about a single step of execution. That’s where the dissection phase of the protocol ends, and Alice must make a one-step proof which will be checked by the EthBridge.

### Why Dissection Correctly Identifies a Cheater

Before talking about the complexities of the real challenge protocol, let’s stop to understand why the simplified version of the protocol is correct. Here correctness means two things: (1) if Alice’s initial claim is correct, Alice can always win the challenge, and (2) if Alice’s initial claim is incorrect, Bob can always win the challenge.

To prove (1), observe that if Alice’s initial claim is correct, she can offer a truthful midpoint claim, and both of the implied half-size claims will be correct. So whichever half Bob objects to, Alice will again be in the position of defending a correct claim. At each stage of the protocol, Alice will be defending a correct claim. At the end, Alice will have a correct one-step claim to prove, so that claim will be provable and Alice can win the challenge.

To prove (2), observe that if Alice’s initial claim is incorrect, this can only be because her claimed endpoint after N steps is incorrect. Now when Alice offers her midpoint state claim, that midpoint claim is either correct or incorrect. If it’s incorrect, then Bob can challenge Alice’s first-half claim, which will be incorrect. If Alice’s midpoint state claim is correct, then her second-half claim must be incorrect, so Bob can challenge that. So whatever Alice does, Bob will be able to challenge an incorrect half-size claim. At each stage of the protocol, Bob can identify an incorrect claim to challenge. At the end, Alice will have an incorrect one-step claim to prove, which she will be unable to do, so Bob can win the challenge.

(If you’re a stickler for mathematical precision, it should be clear how these arguments can be turned into proofs by induction on N.)

### The Real Dissection Protocol

The real dissection protocol is conceptually similar to the simplified one described above, but with several changes that improve efficiency or deal with necessary corner cases. Here is a list of the differences.

**K-way dissection:** Rather than dividing a claim into two segments of size N/2, we divide it into K segments of size N/K. This requires posting K-1 intermediate claims, at points evenly spaced through the claimed execution. This reduces the number of rounds by a factor of log(K)/log(2).

**Answer a dissection with a dissection:** Rather than having each round of the protocol require two moves, where Alice dissects and Bob chooses a segment to challenge, we instead require Bob, in challenging a segment, to post his own claimed endpoint state for that segment (which must differ from Alice’s) as well as his own dissection of his version of the segment. Alice will then respond by identifying a subsegment, posting an alternative endpoint for that segment, and dissecting it. This reduces the number of moves in the game by an additional factor of 2, because the size is cut by a factor of K for every move, rather than for every two moves.

**Dissect by ArbGas, Not By Steps**: Rather than measuring the size of an interval by the number of instructions executed, we measure by the amount of ArbGas it consumes. This allows the protocol to precisely determine how long it will take a validator to check the correctness of a claim (because validator checking time is proportional to ArbGas used) which allows the protocol to more precisely set deadlines for rollup nodes. The drawback of this is that different instructions require different amounts of ArbGas, so we can no longer assume that a segment of execution can end on an exact N/K step boundary. The real protocol allows a claim to end at the first instruction boundary at or after its target endpoint; and the correctness argument accounts for the possibility that parties will lie about where the correct endpoint of a segment is.

**Deal With the Empty-Inbox Case**: The real AVM can’t always execute N ArbGas units without getting stuck. The machine might halt, or it might have to wait because its inbox is exhausted so it can’t go on until more messages arrive. So Bob must be allowed to respond to Alice’s claim of N units of execution by claiming that N steps are not possible. The real protocol thus allows any response (but not the initial claim) to claim a special end state that means essentially that the specified amount of execution is not possible under the current conditions.

**Time Limits:** Each player is given a time allowance. The total time a player uses for all of their moves must be less than the time allowance, or they lose the game. Think of the time allowance as being about a week.

It should be clear that these changes don’t affect the basic correctness of the challenge protocol. They do, however, improve its efficiency and enable it to handle all of the cases that can come up in practice.

### Efficiency

The challenge protocol is designed so that the dispute can be resolved with a minimum of work required by the EthBridge in its role as referee. When it is Alice’s move, the EthBridge only needs to keep track of the time Alice uses, and ensure that her move does include K-1 intermediate points as required. The EthBridge doesn’t need to pay attention to whether those claims are correct in any way; it only needs to know whether Alice’s move “has the right shape”.

The only point where the EthBridge needs to evaluate a move “on the merits” is at the one-step proof, where it needs to look at Alice’s proof and determine whether the proof that was provided does indeed establish that the virtual machine moves from the before state to the claimed after state after one step of computation. We’ll discuss the details of one-step proofs below in the [Arbitrum Virtual Machine](#avm) section.

## 验证者

一些 Arbitrum 节点会选择充当验证者。 验证者会关注 Rollup 协议的运行并参与该协议，安全地推进链状态不断向前。

并非所有节点都会选择这样做。 因为 Rollup 协议不决定链将做什么，而只是确认完全由收件箱消息确定的正确行为，所以节点可以忽略 Rollup 协议并简单地为自己计算正确的行为。 有关此类节点可能执行的操作的更多信息，请参阅完整节点部分。

成为验证者是无需许可的——任何人都可以做到。 Offchain Labs 提供了开源的验证者软件，及预编译的Docker image。

每个验证者都可以选择自己的策略，但我们希望验证者遵循三种常见的策略。

- 主动验证者策略试图通过提议新的 rollup 区块来推进链的状态。 但由于提议rollup区块需要质押，因此活跃的验证者需要一直提供质押。 一条链实际上只需要一个诚实的主动验证者，如果验证者过多其实是对资源的低效利用和浪费。 对于 Arbitrum One 来说，Offchain Labs 在上面一直运行着一个活跃的验证者。
- 防御验证者策略监视 Rollup 协议的运行。 如果提出的 Rollup 区块皆为正确的区块，则此策略的验证者将不会直接参与进网络。 但是，如果有恶意验证者提议了不正确的区块，该策略会通过自行提议正确的区块或在另一方已提议的正确区块上进行质押来干预。 这种策略在网络进展顺利时可以避免自己质押，但如果有人试图作弊，它将会进行质押以捍卫结果的正确。
- The _watchtower validator_ strategy never stakes. 它只是监视 Rollup 协议网络，如果有恶意验证者提议了不正确的区块，它就会发出警报（通过它选择的任何方式），以便其他验证者可以进行干预。 该策略假设愿意进行质押的其他各方会进行干预，以获取不诚实提议者的一些质押，并且这可能会在不诚实区块的截止日期到期之前发生。 （在实际环境中，这将允许几天的相应。）

Under normal conditions, validators using the defensive and watchtower strategies won’t do anything except observe. A malicious actor who is considering whether to try cheating won’t be able to tell how many defensive and watchtower validators are operating incognito. Perhaps some defensive validators will announce themselves, but others probably won’t, so a would-be attacker will always have to worry that defenders are waiting to emerge.

Who will be validators? Anyone can do it, but most people will choose not to. In practice we expect people to validate a chain for several reasons.

- Some validators will be paid, by the party that created the chain or someone else. On the Arbitrum One chain, Offchain Labs will hire some validators.
- Parties who have significant assets at stake on a chain, such as dapp developers, exchanges, power-users, and liquidity providers, may choose to validate in order to protect their investment.
- Anyone who chooses to validate can do so. Some users will probably choose to validate in order to protect their own interests or just to be good citizens. But ordinary users don’t need to validate, and we expect that the vast majority of users won’t.

## AVM: The Arbitrum Virtual Machine

The Arbitrum Virtual Machine (AVM) is the interface between the Layer 1 and Layer 2 parts of Arbitrum. Layer 1 _provides_ the AVM interface and ensures correct execution of the virtual machine. Layer 2 _runs on_ the AVM virtual machine and provides the functionality to deploy and run contracts, track balances, and all of the things a smart-contract-enabled blockchain needs to do.

**Every Arbitrum chain has a single AVM** which does all of the computation and maintains all of the storage for everything that happens on the chain. Unlike some other systems which have a separate “VM” for each contract, Arbitrum uses a single virtual machine for the whole chain, much like Ethereum. The management of multiple contracts on an Arbitrum chain is done by software that runs on top of the AVM.

At its core, a chain’s VM executes in this simple model, consuming messages from its inbox, changing its state, and producing outputs.

![img](https://lh4.googleusercontent.com/qwf_aYyB1AfX9s-_PQysOmPNtWB164_qA6isj3NhkDnmcro6J75f6MC2_AjlN60lpSkSw6DtZwNfrt13F3E_G8jdvjeWHX8EophDA2oUM0mEpPVeTlMbsjUCMmztEM0WvDpyWZ6R)

The starting point for the AVM design is the Ethereum Virtual Machine (EVM). Because Arbitrum aims to efficiently execute programs written or compiled for EVM, the AVM uses many aspects of EVM unchanged. For example, AVM adopts EVM's basic integer datatype (a 256-bit big-endian unsigned integer), as well as the instructions that operate on EVM integers.

### Why AVM differs from EVM

Differences between AVM and EVM are motivated by the needs of Arbitrum's Layer 2 protocol and Arbitrum's use of a interactive proving to resolve disputes.

#### Execution vs. proving

Arbitrum, unlike EVM and similar architectures, supports both execution (advancing the state of a computation by executing it, which is always done off-chain in Arbitrum) and proving (convincing an L1 contract or other trusted party that a claim about execution is correct). EVM-based systems resolve disputes by re-executing the disputed code, whereas Arbitrum relies on a more efficient challenge protocol that leads to an eventual proof.

One nice consequence of separating execution from proving -- and never needing to re-execute blocks of code on an L1 chain -- is that we can optimize execution and proving for the different environments they’ll be used in. Execution is optimized for speed in a local, trusted environment, because local execution is the common case. Proving, on the other hand, will be needed less often but must still be efficient enough to be viable even on the busy Ethereum L1 chain. Proof-checking will rarely be needed, but proving must always be possible. The logical separation of execution from proving allows execution speed to be optimized more aggressively in the common case where proving turns out not to be needed.

#### Requirements from ArbOS

Another difference in requirements is that Arbitrum uses ArbOS, an "operating system" that runs at Layer 2. ArbOS controls the execution of separate contracts to isolate them from each other and track their resource usage. In support of this, the AVM includes instructions to support saving and restoring the machine's stack, managing machine registers that track resource usage, and receiving messages from external callers. These instructions are used by ArbOS itself, but ArbOS ensures that they will never appear in untrusted code.

Supporting these functions in Layer 2 trusted software, rather than building them in to the L1-enforced rules of the architecture as Ethereum does, offers significant advantages in cost because these operations can benefit from the lower cost of computation and storage at Layer 2, instead of having to manage those resources as part of the Layer 1 EthBridge contract. Having a trusted operating system at Layer 2 also has significant advantages in flexibility, because Layer 2 code is easier to evolve, or to customize for a particular chain, than a Layer-1 enforced VM architecture would be.

The use of a Layer 2 trusted operating system does require some support in the virtual machine instruction set, for example to allow the OS to limit and track resource usage by contracts.

#### Supporting Merkleization

Any Layer 2 protocol that relies on assertions and dispute resolution must define a rule for Merkle-hashing the full state of the virtual machine so that claims about parts of the state can be efficiently made to the base layer. That rule must be part of the architecture specification because it is relied upon in resolving disputes. It must also be reasonably efficient for validators to maintain the Merkle hash and/or recompute it when needed. This affects how the architecture structures its memory, for example. Any storage structure that is large and mutable will be relatively expensive to Merkleize, and a specific algorithm for Merkleizing it would need to be part of the architecture specification.

The AVM architecture responds to this challenge by having only bounded-size, immutable memory objects ("Tuples"), which can include other Tuples by reference. Tuples cannot be modified in-place but there is an instruction to copy a Tuple with a modification. This allows the construction of tree structures which can behave like a large flat memory. Applications can use functionalities such as large flat arrays, key-value stores, and so on, by accessing libraries that use Tuples internally.

The semantics of Tuples make it impossible to create cyclic structures of Tuples, so an AVM implementation can safely manage Tuples by using reference-counted, immutable structures. The hash of each Tuple value need only be computed once, because the contents are immutable.

#### Codepoints: Optimizing code for proving

The conventional organization of code is to store a linear array of instructions, and keep a program counter pointing to the next instruction that will be executed. With this conventional approach, proving the result of one instruction of execution requires logarithmic time and space, because a Merkle proof must be presented to prove which instruction is at the current program counter.

The AVM does this more efficiently, by separating execution from proving. Execution uses the standard abstraction of an array of instructions indexed by a program counter, but proving uses an equivalent CodePoint construct that allows proving and proof-checking to be done in constant time and space. The CodePoint for the instruction at some PC value is the pair (opcode at PC, Hash(CodePoint at PC+1)). (If there is no CodePoint at PC+1, then zero is used instead.)

For proving purposes, the "program counter" is replaced by a "current CodePoint hash" value, which is part of the machine state. The preimage of this hash will contain the current opcode, and the hash of the following codepoint, which is everything a proof verifier needs to verify what the opcode is and what the current CodePoint hash value will be after the instruction, if the instruction isn't a Jump.

All jump instructions use jump destinations that are CodePoints, so a proof about execution of a jump instruction also has immediately at hand not only the PC that is being jumped to, but also what the contents of the "current CodePoint hash" register will be after the jump executes. In every case, proof and verification requires constant time and space.

In normal execution (when proving is not required), implementations will typically just use PC values as on a conventional architecture. However, when a one-step proof is needed, the prover can use a pre-built lookup table to get the CodePoint hashes corresponding to any relevant PCs.

#### Creating code at runtime

Code is added to an AVM in two ways. First, some code is created when the AVM starts running. This code is read in from an AVM executable file (a .mexe file) and preloaded by the AVM emulator.

Second, the AVM has three instructions to create new CodePoints: one that makes a new Error CodePoint, and two that make new CodePoints (one for a CodePoint with an immediate value and one for a CodePoint without) given an opcode, possibly an immediate value, and a next CodePoint. These are used by ArbOS when translating EVM code for execution. (For more details on this, see the [ArbOS](#arbos) section.)

#### Getting messages from the Inbox

The _inbox_ instruction consumes the next message from the VM’s inbox and pushes it onto the AVM's Stack. If all messages in the inbox have been consumed already, the inbox instruction blocks--the VM cannot complete the inbox instruction, nor can it do anything else, until a message arrives and the inbox instruction can complete. If the inbox has been completely consumed, any purported one-step proof of executing the inbox instruction will be rejected.

#### Producing outputs

The AVM has two instructions that can produce outputs: _send_ and _log_. Both are hashed into the output hash accumulator that records the (hash of) the VM’s outputs, but _send_ causes its value to be recorded as calldata on the L1 chain, while _log_ does not. This means that outputs produced with send will be visible to L1 contracts, while those produced with *log* will not. Of course, sends are more expensive than logs. A useful design pattern is for a sequence of values to be produced as logs, and then a Merkle hash of those values to be produced as a single send. That allows an L1 contract to see the Merkle hash of the full sequence of outputs, so that it can verify the individual values when it sees them. ArbOS uses this design pattern, as described below.

#### ArbGas and gas tracking

The AVM has a notion of AVM gas, which is like gas on Ethereum. AVM gas measures the cost of executing an instruction, based on how long it will take a validator to execute it. Every AVM instruction has an AVM gas cost.

Arbitrum instructions have different gas costs than their Ethereum counterparts, for two reasons. First, the relative costs of executing Instruction A versus Instruction B can be different on a Layer 2 system versus on Ethereum. For example, storage accesses can be cheaper on Arbitrum relative to add instructions. AVM gas costs are based on the relative cost on Arbitrum.

The AVM architecture has a machine register called AVM Gas Remaining. Before executing any instruction, the AVM gas cost of that instruction is deducted from AVM Gas Remaining. If this would underflow the register (indicating that the execution is “out of AVM gas”) a hard error is generated and the AVM Gas Remaining register is set to MaxUint256.

The AVM has instructions to get and set the AVM Gas Remaining register, which ArbOS uses to limit and count the AVM gas used by user contracts.

(For usability reasons, the Arbitrum API exposes "ArbGas" rather than "AVM gas", where 1 ArbGas is defined to be equal to 100 AVM gas.  This makes gas amounts and gas prices more intuitive and more consistent with legacy user interfaces from tools like wallets.)

For information on ArbGas prices and other fee-related matters, see the Fees section.

#### Error handling

Error conditions can arise in AVM execution in several ways, including stack underflows, AVM gas exhaustion, and type errors such as trying to jump to a value that is not a CodePoint.

The AVM architecture has an Error CodePoint register that can be read and written by special instructions. When an error occurs, the Next CodePoint register is set equal to the Error CodePoint register, essentially jumping to the specified error handler.

## ArbOS

ArbOS is a trusted "operating system” at Layer 2 that isolates untrusted contracts from each other, tracks and limits their resource usage, and manages the economic model that collects fees from users to fund the operation of a chain. When an Arbitrum chain is started, ArbOS is pre-loaded into the chain’s AVM instance, and ready to run. After some initialization work, ArbOS sits in its main run loop, reading a message from the inbox, doing work based on that message including possibly producing outputs, then circling back to get the next message.

### Why ArbOS?

In Arbitrum, much of the work that would otherwise have to be done expensively at Layer 1 is instead done by ArbOS, trustlessly performing these functions at the speed and low cost of Layer 2.

Supporting these functions in Layer 2 trusted software, rather than building them in to the L1-enforced rules of the architecture as Ethereum does, offers significant advantages in cost because these operations can benefit from the lower cost of computation and storage at Layer 2, instead of having to manage those resources as part of the Layer 1 EthBridge contract. Having a trusted operating system at Layer 2 also has significant advantages in flexibility, because Layer 2 code is easier to evolve, or to customize for a particular chain, than a Layer-1 enforced VM architecture would be.

The use of a Layer 2 trusted operating system does require some support in the architecture, for example to allow the OS to limit and track resource usage by contracts. The AVM architecture provides that support.

For a detailed specification describing the format of messages used for communication between clients, the EthBridge, and ArbOS, see the [ArbOS Message Formats Specification](ArbOS_Formats.md).

## EVM Compatibility

ArbOS provides functionality to emulate the execution of an Ethereum-compatible chain. It tracks accounts, executes contract code, and handles the details of creating and running EVM code. Clients can submit EVM transactions, including the ones that deploy contracts, and ArbOS ensures that the submitted transactions run in a compatible manner.

### The account table

ArbOS maintains an account table, which keeps track of the state of every account in the emulated Ethereum chain. The table entry for an account contains the account’s balance, its nonce, its code and storage (if it is a contract), and some other information associated with Arbitrum-specific features. An account’s entry in the table is initialized the first time anything happens in the account on the Arbitrum chain.

### Translating EVM code to run on AVM

EVM code can’t run directly on the AVM architecture, so ArbOS has to translate EVM code into equivalent AVM code in order to run it. This is done within ArbOS to ensure that it is trustless.

(Some old versions of Arbitrum used a separate compiler to translate EVM to AVM code, but that had significant disadvantages in both security and functionality, so we switched to built-in translation in ArbOS.)

ArbOS takes an EVM contract’s program and translates it into an AVM code segment that has equivalent functionality. Some instructions can be translated directly; for example an EVM add instruction translates into a single AVM add instruction. Other instructions translate into a call to a library provided by ArbOS. For example, the EVM _CREATE2_ instruction, which creates a new contract whose address is computed in a special way, translates into a call to an ArbOS function called _evmOp_create2_.

To deploy a new contract, ArbOS takes the submitted EVM constructor code, translates it into AVM code for the constructor, and runs that code. If it completes successfully, ArbOS takes the return data, interprets it as EVM code, translates that into AVM code, and then installs that AVM code into the account table as the code for the now-deployed contract. Future calls to the contract will jump to the beginning of that AVM code.

### More EVM emulation details

When an EVM transaction is running, ArbOS keeps an EVM Call Stack, a stack of EVM Call Frames which represent the nested calls inside of the transaction. Each EVM Call Frame records the data for one level of call. When an inner call returns or reverts, ArbOS cleans up its call frame, and either propagates the effects of the call (if the call returned) or discards them (if the call reverted).

The EVM call family of instructions (call, delegatecall, etc.) invoke ArbOS library functions that create new EVM Call Frames according to the EVM-specified behavior of the call type that was made, including propagation of calldata and gas. Any gas left over after a call is returned to the caller, as on Ethereum.

Certain errors in executing EVM, such as stack underflows, will trigger a corresponding error during AVM emulation. ArbOS’s error handler detects that the error occurred while emulating a certain EVM call, and reverts that call accordingly, returning control to its caller or providing a transaction receipt as appropriate. ArbOS distinguishes out-of-gas errors from other errors by looking at the AVM Gas Remaining register, which is automatically set to MaxUint256 if an out-of-gas error occurred.

The result of these mechanisms is that EVM code can run compatibly on Arbitrum.

There are three main differences between EVM execution on Arbitrum compared to Ethereum.

First, the two EVM instructions DIFFICULTY and COINBASE, which don’t make sense on an L2 chain, return fixed constant values.

Second, the EVM instruction BLOCKHASH returns a pseudorandom value that is a digest of the chain’s history, but not the same hash value that Ethereum would return at the same block number.

Third, Arbitrum uses the ArbGas system so everything related to gas is denominated in ArbGas, including the gas costs of operations, and the results of gas-related instructions like GASLIMIT and GASPRICE.

### Deploying EVM contracts

On Ethereum, an EVM contract is deployed by sending a transaction to the null account, with calldata consisting of the contract’s constructor. Ethereum runs the constructor, and if the constructor succeeds, its return data is set up as the code for the new contract.

Arbitrum uses a similar pattern. To deploy a new EVM contract, ArbOS takes the submitted EVM constructor code, translates it into AVM code for the constructor, and runs that AVM code. If it completes successfully, ArbOS takes the return data, interprets it as EVM code, translates that into AVM code, and then installs that AVM code into the account table as the code for the now-deployed contract. Future calls to the contract will jump to the beginning of that AVM code.

### Transaction receipts

When an EVM transaction finishes running, whether or not it succeeded, ArbOS issues a transaction receipt, using the AVM _log_ instruction. The receipt is detected by Arbitrum nodes, which can use it to provide results to users according to the standard Ethereum RPC API.

## Full Nodes

As the name suggests, full nodes in Arbitrum play the same role that full nodes play in Ethereum: they know the state of the chain and they provide an API that others can use to interact with the chain.

Arbitrum full nodes operate ["above the line"](#above-or-below-the-line), meaning that they don’t worry about the rollup protocol but simply treat their Arbitrum chain as a machine consuming inputs to produce outputs. A full node has a built-in AVM emulator that allows it to do this.

### Batching transactions: full node as an aggregator

One important role of a full node is serving as an aggregator, which means that the full node receives a set of signed transactions from users and assembles them into a batch which it submits to the chain’s inbox as a single unit. Submitting transactions in batches is more efficient than one-by-one submission, because each submission is an L1 transaction to the EthBridge, and Ethereum imposes a base cost of 21,000 L1 gas per transaction. Submitting a batch allows that fixed cost (and some other fixed costs) to be amortized across a larger group of user transactions. That said, submitting a batch is permissionless, so any user can, say, submit a single transaction "batch" if the need arises; Arbitrum thereby inherits the same censorship resistance as the Ethereum.

### Compressing transactions

In addition to batching transactions, full nodes can also compress transactions to save on L1 calldata space. Compression is transparent to users and to contracts running on Arbitrum--they see only normal uncompressed transactions. The process works like this: the user submits a normal transaction to a full node; the full node compresses the transactions and submits it to the chain; ArbOS receives the transaction and uncompresses it to recover the original transaction; ArbOS verifies the signature on the transaction and processes the transaction.

Compression can make the “header information” in a transaction much smaller. Full nodes typically use both compression and batching when submitting transactions.

### Aggregator costs and fees

An aggregator that submits transactions on behalf of users will have costs due to the L1 transactions it uses to submit those transactions to the Inbox contract. Arbitrum includes a facility to collect fees from users, to reimburse the aggregator for its costs. This is detailed in the [ArbGas and Fees](#arbgas-and-fees) section.

## Sequencer Mode

Sequencer mode is an optional feature of Arbitrum chains, which can be turned on or off for each chain.  We expect it to be enabled for most chains. Arbitrum One uses a sequencer that is operated by Offchain Labs.

The sequencer is a specially designated full node, which is given limited power to control the ordering of transactions. This allows the sequencer to guarantee the results of user transactions immediately, without needing to wait for anything to happen on Ethereum. So no need to wait five minutes or so for block confirmations--and no need to even wait 15 seconds for Ethereum to make a block.

Clients interact with the sequencer in exactly the same way they would interact with any full node, for example by giving their wallet software a network URL that happens to point to the sequencer.

### Instant confirmation

Without a sequencer, a node can predict what the results of a client transaction will be, but the node can't be sure, because it can't know or control how the transactions it submits will be ordered in the inbox, relative to transactions submitted by other nodes.

The sequencer is given more control over ordering, so it has the power to assign its clients' transactions a position in the inbox queue, thereby ensuring that it can determine the results of client transactions immediately. The sequencer's power to reorder has limits (see below for details) but it does have more power than anyone else to influence transaction ordering.

### Inboxes, fast and slow

When we add a sequencer, the operation of the inbox changes.

* Only the sequencer can put new messages directly into the inbox. The sequencer tags the messages it is submitting with an Ethereum block number and timestamp. (ArbOS ensures that these are non-decreasing, adjusting them upward if necessary to avoid decreases.)
* Anyone else can submit a message, but messages submitted by non-sequencer nodes will be put into the "delayed inbox" queue, which is managed by an L1 Ethereum contract.
  * Messages in the delayed inbox queue will wait there until the sequencer chooses to "release" them into the main inbox, where they will be added to the end of the inbox.  A well-behaved sequencer will typically release delayed messages after about ten minutes, for reasons explained below.
  * Alternatively, if a message has been in the delayed inbox queue for longer than a maximum delay interval (currently 24 hours) then anyone can force it to be promoted into the main inbox. (This ensures that the sequencer can only delay messages but can't censor them.)

### If the sequencer is well-behaved...

A well-behaved sequencer will accept transactions from all requesters and treat them fairly, giving each one a promised transaction result as quickly as it can.

It will also minimize the delay it imposes on non-sequencer transactions by releasing delayed messages promptly, consistent with the goal of providing strong promises of transaction results. Specifically, if the sequencer believes that 40 confirmation blocks are needed to have good confidence of finality on Ethereum, then it will release delayed messages after 40 blocks. This is enough to ensure that the sequencer knows exactly which transactions will precede its current transaction, because those preceding transactions have finality. There is no need for a benign sequencer to delay non-sequencer messages more than that, so it won't.

This does mean that transactions that go through the delayed inbox will take longer to get finality. Their time to finality will roughly double, because they will have to wait one finality period for promotion, then another finality period for the Ethereum transaction that promoted them to achieve finality.

This is the basic tradeoff of having a sequencer: if your message uses the sequencer, finality is C blocks faster; but if your message doesn't use the sequencer, finality is C blocks slower. This is usually a good tradeoff, because most transactions will use the sequencer; and because the practical difference between instant and 10-minute finality is bigger than the difference between 10-minute and 20-minute finality.

So a sequencer is generally a win, if the sequencer is well behaved.

### If the sequencer is malicious...

A malicious sequencer, on the other hand, could cause some pain. If it refuses to handle your transactions, you're forced to go through the delayed inbox, with longer delay. And a malicious sequencer has great power to front-run everyone's transactions, so it could profit greatly at users' expense.

On Arbitrum One, Offchain Labs runs a sequencer which is well-behaved--we promise!. This will be useful but it's not decentralized. Over time, we'll switch to decentralized, fair sequencing, as described below.

Because the sequencer will be run by a trusted party at first, and will be decentralized later, we haven't built in a mechanism to directly punish a misbehaving sequencer. We're asking users to trust the centralized sequencer at first, until we switch to decentralized fair sequencing later.

### Decentralized fair sequencing

Viewed from 30,000 feet, decentralized fair sequencing isn't too complicated. Instead of being a single centralized server, the sequencer is a committee of servers, and as long as a large enough supermajority of the committee is honest, the sequencer will establish a fair ordering over transactions.

How to achieve this is more complicated. Research by a team at Cornell Tech, including Offchain Labs CEO and Co-founder Steven Goldfeder, developed the first-ever decentralized fair sequencing algorithm. With some improvements that are under development, these concepts will form the basis for our longer-term solution, of a fair decentralized sequencer.

## Bridging

We have already covered how users interact with L2 contracts--they submit transactions by putting messages into the chain’s inbox, or having a full node sequencer or aggregator do so on their behalf. Let’s talk about how contracts interact between L1 and L2--how an L1 contract calls an L2 contract, and vice versa.

The L1 and L2 chains run asynchronously from each other, so it is not possible to make a cross-chain call that produces a result within the same transaction as the caller. Instead, cross-chain calls must be asynchronous, meaning that the caller submits the call at some point in time, and the call runs later. As a consequence, a cross-chain contract-to-contract call can never produce a result that is available to the calling contract (except for acknowledgement that the call was successfully submitted for later execution).

### L1 contracts can submit L2 transactions

An L1 contract can submit an L2 transaction, just like a user would, by calling the EthBridge. This L2 transaction will run later, producing results that will not be available to the L1 caller. The transaction will execute at L2, but the L1 caller won’t be able to see any results from the L2 transaction.

The advantage of this method is that it is simple and has relatively low latency. The disadvantage, compared to the other method we’ll describe soon, is that the L2 transaction might revert if the L1 caller doesn’t get the L2 gas price and max gas amount right. Because the L1 caller can’t see the result of its L2 transaction, it can’t be absolutely sure that its L2 transaction will succeed.

This would introduce a serious a problem for certain types of L1 to L2 interactions. Consider a transaction that includes depositing a token on L1 to be made available at some address on L2. If the L1 side succeeds, but the L2 side reverts, you've just sent some tokens to the L1 inbox contract that are unrecoverable on either L2 or L1. Not good.

### L1 to L2 ticket-based transactions

Fortunately, we have another method for L1 to L2 calls, which is more robust against gas-related failures, that uses a ticket-based system. The idea is that an L1 contract can submit a “pre-packaged” transaction and immediately receive a “ticketID” that identifies that submission. Later, anyone can call a special pre-compiled contract at L2, providing the ticketID, to try redeeming the ticket and executing the transaction.

The pre-packaged transaction includes the sender’s address, a destination address, a callvalue, and calldata. All of this is saved, and the callvalue is deducted from the sender’s account and (logically) attached to the pre-packaged transaction.

If the redemption succeeds, the transaction is done, a receipt is issued for it, and the ticketID is canceled and can’t be used again. If the redemption fails, for example because the packaged transaction fails, the redemption reports failure and the ticketID remains available for redemption.

As an option (and by default), the original submitter can try to redeem their submitted transaction immediately, at the time of its submission, in the hope that this redemption will succeed. As an example, our "token deposit" use case above should, in the happy, common case, still only require a single signature from the user. If this instant redemption fails, the ticketID will still exist as a backstop which others can redeem later.

Submitting a transaction in this way carries a price in ETH which the submitter must pay, which varies based on the calldata size of the transaction. Once submitted, the ticket is valid for about a week. It will remain valid after that, as long as someone pays weekly rent to keep it alive. If the rent goes unpaid and the ticket has not been redeemed, it is deleted.

When the ticket is redeemed, the pre-packaged transaction runs with sender and origin equal to the original submitter, and with the destination, callvalue, and calldata the submitter provided at the time of submission. (The submitter can specify an address to which the callvalue will be refunded if the transaction is dropped for lack of rent without ever being redeemed.)

This rent-based mechanism is a bit more cumbersome than direct L1 to L2 transactions, but it has the advantage that the submission cost is predictable and the ticket will always be available for redemption if the submission cost is paid. As long as there is some user who is willing to redeem the ticket (and pay rent if needed), the L2 transaction will eventually be able to execute and will not be silently dropped.

### L2 to L1 ticket-based calls

Calls from L2 to L1 operate in a similar way, with a ticket-based system. An L2 contract can call a method of the precompiled ArbSys contract, to send a transaction to L1. When the execution of the L2 transaction containing the submission is confirmed at L1 (some days later), a ticket is created in the EthBridge. That ticket can be triggered by anyone who calls a certain L1 EthBridge method and submits the ticketID. The ticket is only marked as redeemed if the L1 transaction does not revert.

These L2-to-L1 tickets have unlimited lifetime, until they’re successfully redeemed. No rent is required, as the costs are covered by network fees that are collected elsewhere in Arbitrum.

## Gas and Fees

ArbGas is used by Arbitrum to track the cost of execution on an Arbitrum chain. It is similar in concept to Ethereum gas, in the sense that every Arbitrum Virtual Machine instruction has an ArbGas cost, and the cost of a computation is the sum of the ArbGas costs of the instructions in it.

ArbGas is not directly comparable to Ethereum gas. In general an Arbitrum chain can consume many more ArbGas units per second of computation, compared to the number of Ethereum gas units in Ethereum's gas limit. Developers and users should think of ArbGas as much more plentiful and much cheaper per unit than Ethereum gas.

[A note on terminology: In reality, there are two related notions of gas in Arbitrum: AVM gas which is tracked by the virtual machine execution, and ArbGas which is used in the the API. The two are strictly related because 1 ArbGas = 100 AVM gas.  To simplify the discussion, this section uses the single term ArbGas and ignores the factor-of-100 conversions that are done correctly by the Arbitrum code.]

### Why ArbGas?

One of the design principles of the Arbitrum Virtual Machine (AVM) is that every instruction should take a predictable amount of time to validate, prove, and proof-check. As a corollary, we want a way to count or estimate the time required to validate any computation.

There are two reasons for this. First, we want to ensure that proof-checking has a predictable cost, so we can predict how much L1 gas is needed by the EthBridge and ensure that the EthBridge will never come anywhere close to the L1 gas limit.

Second, accurate estimation of validation time is important to maximize the throughput of a rollup chain, because it allows us to set the chain's speed limit safely.

### ArbGas in rollup blocks

Every rollup block includes an amount of ArbGas used by the computation so far, which implies an amount used since the predecessor rollup block. Like everything else in the rollup block, this value is only a claim made by the staker who created the block, and the block will be defeatable in a challenge if the claim is wrong.

Although the ArbGas value in a rollup block might not be correct, it can be used reliably as a limit on how much computation is required to validate the block. This is true because a validator who is checking the block can cut off their computation after that much ArbGas has been consumed; if that much ArbGas has been consumed without reaching the end of the rollup block, then the rollup block must be wrong and the checker can safely challenge it. For this reason, the rollup protocol can safely use the ArbGas claim in a rollup block, minus the amount in the predecessor block, as an upper bound on the time required to validate the rollup block’s correctness.

A rollup block can safely be challenged even if the ArbGas usage is the only aspect of the block that is false. When a claim is bisected, the claims will include (claimed) ArbGas usages, which must sum to the ArbGas usage of the parent claim. It follows that if the claim's ArbGas amount is wrong, at least one of the sub-claims must have a wrong ArbGas amount. So a challenger who knows that a claim's ArbGas amount is wrong will always be able to find a sub-claim that has a wrong ArbGas amount.

Eventually the dispute will get down to a single AVM instruction, with a claim about that instruction's ArbGas usage. One-step proof verification checks if this claim is correct. So a wrong ArbGas claim in a rollup block can be pursued all the way down to a single instruction with a wrong ArbGas amount--and then the wrongness will be detected by the one-step proof verification in the EthBridge.

### ArbGas accounting in the AVM

The AVM architecture also does ArbGas accounting internally, using a machine register called AVM Gas Remaining, which is a 256-bit unsigned integer that behaves as follows:

- The register is initially set to MaxUint256.
- Immediately before any instruction executes, that instruction's AVM gas cost is subtracted from the register. If this would make the register's value less than zero, an error is generated and the register's value is set to MaxUint256. (The error causes a control transfer as specified in the AVM specification.)
- A special instruction can be used to read the register's value.
- Another special instruction can be used to set the register to any desired value.

This mechanism allows ArbOS to control and account for the ArbGas usage of application code. ArbOS can limit an application call's use of ArbGas to N units by setting the register to N before calling the application, then catching the out-of-ArbGas error if it is generated. At the beginning of the runtime's error-handler, ArbOS would read the AVM Gas Remaining register, then set the register to MaxUint256 to ensure that the error-handler could not run out of ArbGas. If the read of the register gave a value close to MaxInt256, then it must be the case that the application generated an out-of-ArbGas error. (It could be the case that the application generates a different error while a small amount of ArbGas remains, then an out-of-ArbGas error occurs at the very beginning of the error-handler. In this case, the second error would set the AVM Gas Remaining register to MaxInt256 and throw control back to the beginning of the error-handler, causing the error-handler to conclude that an out-of-ArbGas error was caused by the application. This is a reasonable behavior which we will consider to be correct.)

If the application code returns control to the runtime without generating an out-of-ArbGas error, the runtime can read the AVM Gas Remaining register and subtract to determine how much ArbGas the application call used. This can be charged to the application's account.

The runtime can safely ignore the ArbGas accounting mechanism. If the special instructions are never used, the register will be set to MaxInt256, and will decrease but in practice will never get to zero, so no error will ever be generated.

The translator that turns EVM code into equivalent AVM code will never generate the instruction that sets the ArbGasRemaining register, so untrusted code cannot manipulate its own gas allocation.

### The Speed Limit

The security of Arbitrum chains depends on the assumption that when one validator creates a rollup block, other validators will check it and issue a challenge if it is wrong. This requires that the other validators have the time and resources to check each rollup block in time to issue a timely challenge. The Arbitrum protocol takes this into account in setting deadlines for rollup blocks.

This sets an effective speed limit on execution of an Arbitrum VM: in the long run the VM cannot make progress faster than a validator can emulate its execution. If rollup blocks are published at a rate faster than the speed limit, their deadlines will get farther and farther in the future. Due to the limit, enforced by the rollup protocol contracts, on how far in the future a deadline can be, this will eventually cause new rollup blocks to be slowed down, thereby enforcing the effective speed limit.

Being able to set the speed limit accurately depends on being able to estimate the time required to validate an AVM computation, with some accuracy. Any uncertainty in estimating validation time will force us to set the speed limit lower, to be safe. And we do not want to set the speed limit lower, so we try to enable accurate estimation.

### Fees

User transactions pay fees, to cover the cost of operating the chain. These fees are assessed and collected by ArbOS at L2. They are denominated in ETH. Some of the fees are immediately paid to the aggregator who submitted the transaction (if there is one, and subject to some limitations discussed below). The rest go into a network fee pool that is used to pay service providers who help to enable the chain’s secure operation, such as validators.

Fees are charged for four resources that a transaction can use:

- _L2 tx_: a base fee for each L2 transaction, to cover the cost of servicing a transaction
- _L1 calldata_: a fee per units of L1 calldata directly attributable to the transaction (as on Ethereum, each non-zero byte of calldata is 16 units, and each zero byte of calldata is 4 units)
- _computation_: a fee per unit of ArbGas used by the transaction
- _storage_: a fee per location of EVM contract storage, based change in EVM storage usage due to the transaction

Each of these four resources has a price, which may vary over time. The resource prices, which are denominated in ETH (more precisely, in wei), are set as follows:

#### Prices for L2 tx and L1 calldata

The prices of the first two resources, L2 tx and L1 calldata, depend on the L1 gas price. ArbOS can’t directly see the L1 gas price, so it estimates the L1 gas prices, based on the L1 Ethereum base fee paid by certain recent EthBridge transactions.

- The base price of an L2 transaction is set by each aggregator, using an Arbitrum precompile, subject to a system-wide maximum.
- The base price of a unit of L1 calldata is just the estimated L1 gas price.

If the transaction was submitted by an aggregator, ArbOS collects these base fees for L2 tx and L1 calldata, and credits that amount immediately to the aggregator. ArbOS also adds a 15% markup and deposits those funds into the network fee account, to help cover overhead and other chain costs. If the transaction was not submitted by an aggregator, ArbOS collects only the 15% portion and credits that to the network fee account.

In order for an aggregator to be reimbursed for submitting a transaction, three things must be true:

1. The transaction’s nonce is correct. [This prevents an aggregator from resubmitting a transaction to collect multiple reimbursements for it.]
2. The transaction’s sender has ETH in its L2 account to pay the fees.
3. The aggregator is listed as the sender’s “preferred aggregator”. (ArbOS records a preferred aggregator for each account, with the default being a specific aggregator address. On Arbitrum One, the default aggregator is the sequencer run by Offchain Labs.) [The preferred aggregator mechanism prevents an aggregator from front-running another aggregator’s batches to steal its reimbursements.]

If these conditions are not all met, the transaction is treated as not submitted by an aggregator so only the network fee portion of the fee is collected.

#### Price for storage

Transactions are charged a storage fee for allocating an EVM storage cell. (Here, "allocating" means changing the value in a cell from zero to a non-zero value, and "deallocating" means changing a cell from a non-zero to a zero value.)  If a cell was allocated within a transaction, and is later deallocated *within the same transaction*, the allocation fee will be refunded when the transaction completes.

Contract creation is charged one storage fee for every 32 bytes of code in the contract. However, if a newly created contract has the same deployed code as an already existing contract, ArbOS will usually detect this and keep only a single copy of the code, thereby saving the second contract from having to pay for code storage.

Each storage allocation costs 2000 times the estimated L1 gas price. This means that storage costs about 10% as much as it does on the L1 chain.

#### Price for ArbGas

ArbGas pricing depends on a minimum price, and a congestion pricing mechanism.

The minimum ArbGas price is set equal to the estimated L1 gas price divided by 100. The price of ArbGas will never go lower than this.

The price will rise above the minimum if the chain is starting to get congested. The idea is similar to Ethereum, to deal with a risk of overload by raising the price of gas enough that demand will meet supply. The mechanism is inspired by Ethereum’s EIP-1559, which uses a base price that, at the beginning of each block, is multiplied by a factor between 7/8 and 9/8, depending on how busy the chain seems to be. When the demand seems to be exceeding supply, the factor will be more than 1; when supply exceeds demand, the factor will be less than 1. (But the price never goes below the minimum.)

The automatic adjustment mechanism depends on an “ArbGas pool” that is tracked by ArbOS. The ArbGas pool has a maximum capacity that is equal to 12 minutes of full-speed computation at the chain’s speed limit. ArbGas used by transactions is subtracted from the gas pool, and at the beginning of each new Ethereum block, ArbGas is added to the pool corresponding to full-speed execution for the number of timestamp seconds since the last block (subject to the maximum pool capacity).

After adding the new gas to the pool, if the new gas pool size is G, the current ArbGas price is multiplied by (16200S - G) / (14400S) where S is the ArbGas speed limit of the chain. This quantity will be 7/8 when G = 720S (the maximum gas pool size) and it will be 9/8 when G = 0.

### The congestion limit

The gas pool is also used to limit the amount of gas available to transactions at a particular timestamp. In particular, if a transaction could require more gas than is available in the gas pool, that transaction is rejected without being executed, returning a transaction receipt indicating that the transaction was dropped due to congestion. This prevents the chain from building up a backlog that is very long--if transactions are being submitted consistently faster than they can be validated, eventually the gas pool will become empty and transactions will be dropped. Meanwhile the transaction price will be escalating, so that the price mechanism will be able to bring supply and demand back into alignment.

### ArbGas accounting and the second-price auction

As on Ethereum, Arbitrum transactions submit a maximum gas amount (here, “maxgas” for short) and a gas price bid (here, “gasbid” for short). A transaction will use up to its maxgas amount of gas, or will revert if more gas would be needed.

On Ethereum, the gas price paid by a transaction is equal to its gasbid. Arbitrum, by contrast, treats the gasbid as the maximum amount the transaction is willing to pay for gas. The actual price paid is equal to the current Arbitrum ArbGas price, whatever that is, as long as it is less than or equal to the transaction’s gasbid. If the transaction’s gasbid is less than the current Arbitrum gas price, the transaction is dropped and a transaction receipt issued, saying that the transaction’s gasbid was too low.

So Arbitrum transactions shouldn’t try to “game” their gasbid by trying to match it too closely to the current ArbGas price. Instead, transactions should set their gasbid equal to the maximum price they’re willing to pay for ArbGas, with the caveat that the sender must have at least gasbid\*maxgas in its L2 ETH account.
