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

Rollup协议的核心安全属性是_AnyTrust Guarantee_（“一诚则成”原理）：只要有一个诚实的验证者，那么整个链的正确运行就会有绝对的保证。 这意味着Arbitrum链的运行是与以太坊一样免信任的。 你或者你雇佣的人可以确保你的交易被正确处理。 不管有多少恶意的人都无法阻止你。

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

- 该区块的父区块是最新确认区块，且
- 该区块的截止时间已经过了，且
- 至少有一个质押者，且
- 所有质押者均质押在该区块上

首个待决区块满足下列情况会被拒绝：

- 该区块的父区块已被拒绝，或
- 下面几点皆为真：
  - 该区块的截止时间已经过了，且
  - 至少有一个质押者，且
  - 没有质押者质押在该区块上。

这一系列规则的结果是，一旦首个待决区块的截止时间已过（假设当前有至少一名质押者质押在了除最新确认区块以外的其他地方），该区块仍是待决状态只有一种可能：至少有一名质押者质押在其上，至少有一名质押者质押在其兄弟区块上。 如果发生了这种情况，双方互不认同。 就要进行挑战解决争议了。

## 挑战

假设rollup链的状态如下：

![img](https://lh4.googleusercontent.com/kAZY9H73dqcHvboFDby9nrtbYZrbsHCYtE5X9NIZQsvcz58vV0WUWUq1xsYKzYWQSc1nPZ8W86LLX0lD3y-ctEaG2ISa2Wpz2pYxTzW09P1UvqSDuoqkHlGDYLLMTzLqX4rlP8Ca)

区块93和95是兄弟区块（父区块皆为92）。 Alice质押于93而Bob质押于95。

目前我们可知Alice和Bob对区块93的正确性有争议，Alice承诺93是正确的而Bob承诺93是错误的。 （Bob质押于95，而95之前的最新确认区块是92，这暗示了93是错的。）

只要双方质押了兄弟区块，且分割双方没有在既有挑战中，任何人都可以对他们进行挑战。 Rollup协议会记录下本次挑战并充当仲裁，最终会宣布胜者并没收失败者的质押资金。 失败者不再是质押者。

挑战是一场Alice和Bob交替出手的博弈，以一个以太坊作合约作为仲裁。 Alice，作为辩护者，最先行动。

博弈分为两个阶段：分割，之后是单步证明。 分割会缩窄二人的争议范围，直至有争议的操作只有一条。 随后单步证明会决定谁的主张是对的。

我们会分两次讲述这部分的协议。 首先，会给出一个精简版，易于理解但效率不够高。 然后还会给出一个真实实现版本。

### 分割协议：精简版

Alice为自己的主张辩护，她的主张是：从父区块的状态开始，虚拟机的状态可以前进至她所主张的区块A上的状态。本质上，她是在宣称，虚拟机可以执行N条指令，消耗M条收件箱中的信息并将哈希从H'转换为H。

Alice的第一个动作需要她把她的断言从开始（0条指令已执行）到结束（N条指令已执行）以中间点切分。 协议要求Alice将其主张对半切分，发布中间点在执行了N/2步指令后的的状态。

当Alice已经有效地将她的断言二等分变为两个N/2步的断言后， Bob需要在这两个片段中选择一段并声明它是错的。

在此，我们又回到了之前的状态：Alice主张一个断言，Bob不同意。 不过现在我们已经把断言长度从N缩短到了N/2。 我们可以再重复之前的动作，Alice二分，Bob选择不同意的那一半，缩短尺度到N/4。 我们可以继续该动作，经过对数轮的博弈，Alice和Bob的争议点就缩减为了单步操作。 自此，分割协议就终止了，Alice必须给EthBridge生成一个单步证明供其检测。

### 为什么分割能够正确分辨作弊者

在我们谈论更复杂的真实挑战协议之前，要停下来思考一下，为什么精简版的协议也是正确的。 这里的正确意味着两点：（1）如果Alice的初始断言是正确的，Alice总会赢得挑战；（2）如果Alice的初始断言是错误的，Bob总会赢得挑战。

欲证明（1）：Alice的初始断言是正确的，则她可以提供一个正确的中间点断言，两侧的半长断言也是正确的。 所以，不论Bob反对哪一侧，Alice还是会为正确的主张辩护。 在协议的任何阶段，Alice都在为正确的主张辩护。 最终的单步辩护也是正确的，Alice会赢得挑战。

欲证明（2）：Alice的初始断言是错误的，只可能是因为她所宣称的终点在经过N步后是错误的。 Alice现在要提供中间点的断言，该断言要么正确要么错误。 如果错误，Bob可以挑战左半边断言，肯定是错的。 如果Alice的中间点是正确的，那另一半断言肯定是错的，Bob就可以挑战右半边的断言。 所以，不论Alice怎样做，Bob都可以找到不正确的半边断言。 而在接下来的每一轮中，Bob都可以对他认为不正确的断言进行挑战。 最终，Alice无法提供正确的单步证明，Bob将赢得挑战。

（如果你是一个非常在意数学形式的人，显然这些结论是可以由基于N的归纳法得出的。）

### 真实的分割协议

真实的分割协议在理念上与上面的精简版是近似的，不过有了一些对效率和边界情况的提升。 下面是两者的区别。

**K式分割**将断言分割为N/K长度的K段，而非N/2长度的N段。 所以需要发布K-1个均匀分布的中间点断言。 该方法使降低了互动轮数，所需轮数为原轮数除以log(K)/log(2)倍。

**以分割响应分割**：在精简版中每一轮都有两步，Alice进行分割，Bob选择一个片段来挑战。在真实实现中，Bob在挑战一个分段时，需要发布他自己的针对该分段的最终态（和Alice的必须是不同的）以及Bob版本的对该分段的进行的再分割。 Alice则进行回应，找出一个分段，为该分段提供一个最终态，并再进行分割。 这样一来，由于每一次行动（而不是每两次行动）就分割了K次，使博弈轮数又额外除以了2倍。

**以ArbGas而非步数进行分割：**我们用ArbGas消耗量作为分割依据，而非指令的数量。 这使得分割协议能精确地确定验证者需要花多久来检验断言的正确性（因为验证者的检验时间与ArbGas消耗成正比），由此即能让协议为rollup结点设定更加准确的截止时间。 不过，缺点是，不同的指令需要不同量的ArbGas，我们就不能再假设某一段可以在N/K步的边界就能恰好执行完。 真实的协议允许断言在第一个指令边界或在其目标终点后结束；而对正确性争辩也会考虑有人会在界定分段的正确终点上说谎。

**空收件箱场景：**真实的AVM不可能总能一直执行N个ArbGas而从不会卡住。 The machine might halt, or it might have to wait because its inbox is exhausted so it can’t go on until more messages arrive. So Bob must be allowed to respond to Alice’s claim of N units of execution by claiming that N steps are not possible. The real protocol thus allows any response (but not the initial claim) to claim a special end state that means essentially that the specified amount of execution is not possible under the current conditions.

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

One nice consequence of separating execution from proving -- and never needing to re-execute blocks of code on an L1 chain -- is that we can optimize execution and proving for the different environments they’ll be used in. 在一个局部可信的环境中，执行速度是最优化的，因为地方执行是常见情况。 另一方面，正在进行， 即使在繁忙的Ethereum L1链中，也需要更少的时间，但仍然必须足够有效，以使其具有可行性。 很少需要校验，但必须始终有可能进行校验。 The logical separation of execution from proving allows execution speed to be optimized more aggressively in the common case where proving turns out not to be needed.

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

### AVM中的ArbGas计量

AVM也在内部处理ArbGas，它会使用ArbGasRemaining寄存器进行计量，该寄存器是一个256位的无符号整数，行为如下：

- 该寄存器初始值为MaxUint256
- 在执行任何指令之前，该指令的ArbGas会即刻从寄存器中扣除。 If this would make the register's value less than zero, an error is generated and the register's value is set to MaxUint256. (The error causes a control transfer as specified in the AVM specification.)
- A special instruction can be used to read the register's value.
- Another special instruction can be used to set the register to any desired value.

This mechanism allows ArbOS to control and account for the ArbGas usage of application code. ArbOS can limit an application call's use of ArbGas to N units by setting the register to N before calling the application, then catching the out-of-ArbGas error if it is generated. At the beginning of the runtime's error-handler, ArbOS would read the AVM Gas Remaining register, then set the register to MaxUint256 to ensure that the error-handler could not run out of ArbGas. If the read of the register gave a value close to MaxInt256, then it must be the case that the application generated an out-of-ArbGas error. (It could be the case that the application generates a different error while a small amount of ArbGas remains, then an out-of-ArbGas error occurs at the very beginning of the error-handler. In this case, the second error would set the AVM Gas Remaining register to MaxInt256 and throw control back to the beginning of the error-handler, causing the error-handler to conclude that an out-of-ArbGas error was caused by the application. This is a reasonable behavior which we will consider to be correct.)

If the application code returns control to the runtime without generating an out-of-ArbGas error, the runtime can read the AVM Gas Remaining register and subtract to determine how much ArbGas the application call used. This can be charged to the application's account.

The runtime can safely ignore the ArbGas accounting mechanism. If the special instructions are never used, the register will be set to MaxInt256, and will decrease but in practice will never get to zero, so no error will ever be generated.

The translator that turns EVM code into equivalent AVM code will never generate the instruction that sets the ArbGasRemaining register, so untrusted code cannot manipulate its own gas allocation.

### 速度上限

Arbitrum链的安全依赖于一个假设，当一名验证着创建一个rollup区块时，其他验证着会对其进行检测，如果有错误则发起挑战。 这需要其他验证者有时间和资源来检查每个rollup区块并及时提出挑战。 Arbitrum协议把该项作为设置rollup区块挑战截止时间的考虑因素。

这就给AVM的运行设置了实际的速度上限：长远来看VM不可能运行地比验证者检验速度还要快。 如果rollup区块的发布速度比速度上限还快，那截止时间在未来就会越来越长。 由于rollup合约强加未来截止时间最多有多长的限制，最终会使新的rollup区块生成变慢，来确保实际的速度上限。

能够准确地设置速度限制取决于能够以一定的准确性估计验证 AVM 计算所需的时间。 安全起见，任何在验证时间估算方面的不确定性都迫使我们把速度上限设置得低一些。 而我们确实不想把速度上限设低，所以会尝试精确的估算。

### 费用

用户交易支付费用，以支付运营链的成本。 这些费用由 ArbOS 在 L2 评估和收取。 以ETH计价。 其中一部分费用会立即支付给提交该笔交易的聚合器（如果有的话。并且这也受到一些限制，下面会讨论）。 另一部分则进入了网络费用资金池中，用来支付一些保障链安全运行的服务提供者，如验证者。

一笔交易会为四种资源交费：

- L2 tx：每个L2交易的基础费用，支付交易的服务成本
- L1 calldata：该交易对应的每单位L1 calldata的费用（每个非0字节的calldata都是16单位的，每个0字节的calldata都是4个单位）
- 运算：该交易所使用的每单位ArbGas的费用
- 存储：每单位EVM存储空间的费用，由该交易所增加的净EVM空间计算

这四种资源中每一种都有价格，价格可能会随着时间而变化。 其价格以ETH计量（准确的说是wei），设置如下：

#### L2 tx和L1 calldata

这两种资源的价格取决于L1燃气价格。 ArbOS不能直接获取L1的气体价格，所以它根据最近某些EthBridge交易支付的L1以太坊基本费用，获得平均值并估计L1气体价格。

- L2 交易的基本费用由每个聚合器设置，使用 Arbitrum 预编译，需符合全系统的最高限额。
- 每单位 L1 calldata 价格就是估算的L1燃气价格。

如果转账是由聚合器提交的，ArbOS会搜集L2 tx和L1 calldata的基础费用，并立即划转给聚合器。 ArbOS也会多收取15%的费用，并将其存入网络费用账户中，来为经常性开支和其他成本所用。 如果该交易不是由聚合器提交的，ArbOS只会收取多的15%那部分并提交给网络费用池。

为了能补偿聚合器提交交易的成本，下列三点需为真实：

1. 交易的nounce是正确的。 [ 防止聚合器重放骗补。]
2. 该笔交易的sender在L2上有ETH，以支付费用。
3. 该聚合器是该sender的『委托聚合器』。 （ArbOS为每个账户都记录了其委托聚合器。 在 Arbitrum One 上，默认聚合器是 Offchain Labs 运行的排序器。） [ 防止其他聚合器抢跑某聚合器的批次交易并偷走其补贴。]

如果这些条件未全部满足，该交易就不会走聚合器，只会被收取网络资金池的那部分费用。

#### 存储空间价格

交易在分配一个EVM存储单元时被收取存储费。 (这里的"分配 "是指将一个单元的值从零变为非零值，"取消分配 "是指将一个单元的值从非零变为零）。  如果一个单元在一个交易中被分配，后来在同一个交易中被取消分配，分配费将在交易完成后被退还。

合约创建时，对合约中每32字节的代码收取一个存储费。 然而，如果一个新创建的合约与一个已经存在的合约有相同的部署代码，ArbOS通常会检测到这一点，只保留一份代码副本，使第二个合约不必支付代码存储费。

每个存储分配成本是估计L1气体价格的2000倍。 这意味着存储成本大约是L1链上的10%。

#### ArbGas价格

ArbGas定价取决于最小价格，和拥堵价格模型。

最小ArbGas价格为预估的L1燃气价格除以100。 ArbGas的价格不可能比该值还低。

如果链开始拥堵了，价格就会上升。 该想法与以太坊的类似，都通过增加足够的燃气成本来调节供需，防止过载风险。 该机制受EIP-1559启发而来，EIP-1559在每个区块的开始时有一个基础价格，根据链的忙碌程度乘以7/8和9/8两个系数因子。 当需求超越供给，该系数因子会大于1；当供给超越需求时，该系数因子会小于1。 （但价格永不可能低于最小值。）

该动态调整机制基于ArbOS管理的“ArbGas池”。 ArbGas池的最大容量，等于以链全速运行12分钟的计算量。 交易所使用的ArbGas从该池中扣除，在每个新以太坊区块的起始，会根据对应的自上一个区块至今的时间戳秒数来向池中加入ArbGas（会受限于池的最大容量）。

在向池中增加了新的gas后，如果新的燃气池的大小是G，则当前的ArbGas价格会乘以(16200S - G) / (14400S) ，其中S是该链的速度上限。 当G=720S（最大池容量限制）时，这个数量将是7/8，当G=0时，它将是9/8。

### 拥挤限制

燃气池也用来限制在特定时间戳时可用的燃气数量。 具体来说，如果一个交易需要的气体超过气体池的可用量，该交易将被拒绝而不被执行，并返回一个交易收据，表明该交易由于拥堵而被放弃。 这防止了链上挤压过多的交易——如果交易提交速度一直比可验证的速度还快，最终燃气池会被清空，交易会被抛弃。 同时，交易价格也会增加，由该机制调节供需至平衡态。

### ArbGas计量与二次出价竞拍

像以太坊一样，Arbitrum交易也会提交一个最大燃气数量（此处简写为maxgas），以及燃气出价（简写为gasbid）。 一笔交易最多会动用到其声明的maxgas，如果不够则该交易会被回滚。

在以太坊上，一笔交易的燃气价格等于其声明的gasbid。 在Arbitrum则不同，gasbid会视作该交易所愿支付的最高价格。 实际支付的价格是当前Arbitrum的ArbGas价格，不论该值是多少，只要它低于该笔交易的gasbid即可。 如果gasbid低于当前当前的ArbGas价格，该交易会被拒绝，并报告被拒绝的交易结果是：gasbid太低。

所以在Arbitrum进行交易时，不应该去赌如何把gasbid压得尽可能低至当前ArbGas价格。 而是应该设置你愿意出的最高价格，同时需要注意发送者必须有至少 gasbid*maxgas ETH费用在其L2账户中。
