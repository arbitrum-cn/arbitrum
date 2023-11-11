---
id: AVM_Specification
title: Arbitrum VM informal architecture spec
sidebar_label: Arbitrum VM Specification
---

This document describes informally the semantics of the Arbitrum VM architecture. This version is simplified, compared to the one described in the Arbitrum paper published in USENIX Security 2018. This version is also tailored to more closely match the Ethereum data formats and instruction set, to ease implementation of an EVM-to-AVM translator.

We expect that some implementations will optimize to save time and space, provided that the result is equivalent to what is described here.

## Values

A Value can have the following types:

- Integer: a 256-bit integer;
- Codepoint: a Value that represents a point in the executable code (implemented as (operation, nextcodehash);
- Tuple: an array of up to 8 slots, numbered consecutively from zero, with each slot containing a Value;
- Buffer: an array of bytes, up to length 2^64.

Note that integer values are not explicitly specified as signed or unsigned. Where the distinction matters, this specification states which operations treat values as signed and which treat them as unsigned. (Where there is no difference, this spec does not specify signed vs. unsigned.)

The special value None refers to a 0-tuple (a tuple containing 0 elements).

Note that the slots of a Tuple may in turn contain other Tuples. As a result, a Tuple may represent an arbitrary multi-level tree (more precisely, a distributed acyclic graph) of values.

Note that all Values are immutable. As a consequence of this, it is impossible to make a Tuple that contains itself either directly or indirectly (reason: if Tuple A contains Tuple B, then A must have been created after B).

Because Tuples are immutable and form an acyclic structure, it is possible for an implementation to represent a Tuple as a pointer to a small array object, and to use reference counting to manage the lifetime of Tuples.

## Operations

There are two types of operations:

- BasicOp: A simple opcode
- ImmediateOp: A opcode along with a Value

Execution of an operation behaves as follows:

- BasicOp: Execute the opcode according to the instruction definition included below
- ImmediateOp: First push the included Value to the stack. Then execute the opcode as described below

## Stacks

A stack represents a (possibly empty) pushdown stack of Values. Stacks support Push and Pop operations, which have the expected semantics. Doing a Pop operation on a stack that is empty causes the VM to enter the Error state. A stack is represented as either None (for an empty stack) or the 2-tuple [topValue, restOfStack], where restOfStack in turn is a stack.

## Marshaling

Marshaling is an invertible mapping from a Value to an array of bytes. Outside the VM, Values are typically represented in Marshaled form.

Unmarshaling is the inverse operation, which turns an array of bytes into a Value. This document does not specify the Unmarshaling operation, except to say that for all Values V, Unmarshal(Marshal(V)) yields V. If a byte-array A could not possibly have been made by marshaling, then attempting to compute unmarshal(A) raises an Error.

An Integer marshals to

- the byte 0
- 32-byte big-endian representation of the value.

A Codepoint marshals to:

- byte val of 1
- the marshalling of the operation
- 32-byte nextHash value

A BasicOp marshals to:

- byte val of 0
- 1-byte representation of the opcode

A ImmediateOp marshals to:

- byte val of 1
- 1-byte representation of the opcode
- Marshalled value

A Tuple marshals to

- byte val of (3 + the number of items in the tuple)
- the concatenation of the results of marshaling the Value in each slot of the Tuple.

A buffer marshals to

- bytes val of 12
- 32-byte big-endian representation of the length of buffer (LENGTH)
- LENGTH bytes representing the value of the buffer

Length of buffer buf is defined to be the length of smallest prefix pre such that b = pre || post and post contains only zeros.

## Hashing Values

The Hash of an Integer is the Keccak-256 of the 32-byte big endian encoding of the integer, encoded as an Integer in big-endian fashion.

The Hash of a Tuple is computed by concatenating the byte value (3 + number of items in the tuple) followed by the Hashes of the items in tuple, and computing the Keccak-256 of the result, encoded as an Integer in big-endian fashion.

The Hash of a Codepoint containing a BasicOp is computed by concatenating the byte value 1, followed by the 1-byte representation of the opcode, followed by the 32-byte nextHash value, and computing the Keccak-256 of the result, encoded as an Integer in big-endian fashion.

The Hash of a Codepoint containing an ImmediateOp is computed by concatenating the byte value 1, followed by the 1-byte representation of the opcode, followed by the 32-byte Hash of the immediate value, followed by the 32-byte nextHash value, and computing the Keccak-256 of the result, encoded as an Integer in big-endian fashion.

The Hash of a Buffer is the Merkle tree hash of LENGTH first bytes of the buffer (length is rounded up the next power of two), read in 32 byte chunks. Hash of empty buffer is Keccak-256 of 32 zeros. More precisely, ROUNDED_LENGTH is the smallest X such that X <= LENGTH, X >= 32 and there's N such that X = 2\*\*N. Hash of a buffer slice of size 32 is Hash(buf) = Keccak-256(buf), and Hash(buf) = Keccak-256(Hash(buf[0..size/2]) || Hash(buf[size/2..size])).

## Virtual Machine State

The state of a VM is either a special state Halted, or a special state ErrorStop, or an extensive state.

An extensive state of a VM contains the following:

- Current Codepoint: a Codepoint that represents the current point of execution;
- Data Stack: a Stack that is the primary working area for computation;
- Aux Stack: a Stack that provides auxiliary storage;
- Register: a mutable storage cell that can hold a single Value;
- Static: an immutable Value that is initialized when the VM is created;
- AVMGas Remaining: an Integer holding the amount of AVMGas that can be consumed before an Error is generated;
- Error Codepoint: a Codepoint that is meant to be used in response to an Error.
- Pending Message: A Tuple that hold the pending inbox message if there is one

When a VM is initialized, it is in an extensive state. The Data Stack, Aux Stack, Register, AVMGas Remaining, and Error Codepoint are initialized to None, None, None, MaxUint256, and the Codepoint (0, 0), respectively. The entity that creates the VM supplies the initial values of the Current Codepoint and Static.

## Hashing a VM State

If a VM is in the Halted state, its state hash is the Integer 0.

If a VM is in the ErrorStop state, its state hash is the Integer 1.

If a VM is in an extensive state, its state hash is computed by concatenating the hash of the Instruction Stack, the hash of the Data Stack, the hash of the Aux Stack, the hash of the Register, the hash of the Static, the 32-byte big-endian representation of AVMGas Remaining, the hash of the Error Codepoint, and the hash of the pending message, hashing the result using Keccak-256.

## The Runtime Environment

The Runtime Environment is a VM’s interface to the outside world. Certain instructions are described as interacting with the Runtime Environment.

The implementation of the Runtime Environment will vary in different scenarios. In standalone AVM emulators, the Runtime Environment might be controlled by command-line options or a configuration file. In production uses of Arbitrum, the Runtime Environment will be provided by an Arbitrum Validator, and will be specified by Preconditions that form part of Assertions in the Arbitrum Protocol.

The runtime environment will supply values for:

- a sequence of message values representing the VM's inbox

Implementers and developers can assume that the Runtime Environment will satisfy the "time consistency" property: if the timestamp of the previous message was T, the timestamp of the next message will be greater than or equal to T.

## Inbox and Messages

Each VM has an Inbox, which is supplied by the Runtime Environment. The inbox is a sequence of values to be returned upon sequential calls to the inbox instruction (described below), which removes the first message from the sequence and pushes it onto the Data Stack.

Every value in the inbox sequence must be a tuple containing at least two items with the second item being an Integer.

Messages may arrive in the Inbox at any time (but not during the execution of an inbox instruction). Any newly arriving messages will be appended after the messages that were previously in the Inbox.

## Errors

Certain conditions are said to “raise an Error”. If an Error is raised when the Error Codepoint is (0,0,0), then the VM enters the ErrorStop state. If an Error is raised when the Error Codepoint is not (0,0,0), then the Current Codepoint is set equal to the Error Codepoint.

If an instruction raises an Error, the effect of the instruction on the Stack is as follows: first, if the instruction has an immediate value, that value is pushed onto the Stack; then, if the instruction would remove K items from the Stack in the non-error case, K items are removed from the Stack (except that the Stack is left empty if this would underflow the Stack). Similarly, if the instruction would remove L items from the AuxStack in the non-error case, L items are removed from the AuxStack (except that the AuxStack is left empty if this would underflow the AuxStack).

## Blocking

Some instructions are said to “block” until some condition is true. This means that if the condition is false, the instruction cannot complete execution and the VM must stay in the state it was in before the instruction. If the condition is true, the VM can execute the instruction. The result is as if the VM stopped and waited until the condition became true.

## AVMGas

Every instruction consumes some amount of AVMGas. (The overall Arbitrum system also uses a notion of ArbGas, where 1 ArbGas equals 100 AVMGas. The 1:100 ratio was adopted to make the ArbGas amounts exposed by the Arbitrum UI more comprehensible to users.)

The AVMGas costs of instructions might change in the future.

When an instruction is about to be executed, if the AVMGas cost of that instruction is G:

- If AVMGas Remaining < G, AVMGas Remaining is set to MaxUint256 and an Error is raised. The instruction is not executed.
- Otherwise, AVMGas Remaining is reduced by G and the instruction is executed.

## Instructions

A VM that is in the Halted or ErrorStop state cannot execute instructions.

A VM that is in an extensive state can execute an instruction. To execute an instruction, the VM gets the opcode from the Current Codepoint.

If the opcode is not a value that is an opcode of the AVM instruction set, the machine is executed as though the instruction were the error opcode.

If the opcode is valid, but there are not enough items on the stack or auxstack to execute the opcode, first clear whichever of the stack or auxstack that underflowed. Then remove the number of items that would have been consumed from whichever of the stack or auxstack didn't underflow, unless both underflowed in which case both should be cleared. Finally execute the machine as though the instruction were an error opcode.

Otherwise the VM carries out the semantics of the opcode.

If an error is raised while executing the opcode, remove the items from the stack and auxstack that would have been consumed by the opcode. In the case of underflow, remove the minimum of the number of items consumed and the size of the stack.

The instructions are as follows:

<table spaces-before="0">
  <tr>
    <th>
      Opcode
    </th>
    
    <th>
      Nickname
    </th>
    
    <th>
      Semantics
    </th>
    
    <th>
      AVMGas cost
    </th>
  </tr>
  
  <tr>
    <td>
      00s: Arithmetic Operations
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      0x01
    </td>
    
    <td>
      add
    </td>
    
    <td>
      Pop two values (A, B) off the Data Stack. If A and B are both Integers, Push the value A+B (truncated to 256 bits) onto the Data Stack. Otherwise, raise an Error.
    </td>
    
    <td>
      3
    </td>
  </tr>
  
  <tr>
    <td>
      0x02
    </td>
    
    <td>
      mul
    </td>
    
    <td>
      Same as add, except multiply rather than add.
    </td>
    
    <td>
      3
    </td>
  </tr>
  
  <tr>
    <td>
      0x03
    </td>
    
    <td>
      sub
    </td>
    
    <td>
      Same as add, except subtract rather than add.
    </td>
    
    <td>
      3
    </td>
  </tr>
  
  <tr>
    <td>
      0x04
    </td>
    
    <td>
      div
    </td>
    
    <td>
      Pop two values (A, B) off the Data Stack. If A and B are both Integers and B is non-zero, Push A/B (unsigned integer divide) onto the Data Stack. Otherwise, raise an Error.
    </td>
    
    <td>
      4
    </td>
  </tr>
  
  <tr>
    <td>
      0x05
    </td>
    
    <td>
      sdiv
    </td>
    
    <td>
      Pop two values (A, B) off the Data Stack. If A and B are both Integers and B is non-zero, Push A/B (signed integer divide) onto the Data Stack. Otherwise, raise an Error.
    </td>
    
    <td>
      7
    </td>
  </tr>
  
  <tr>
    <td>
      0x06
    </td>
    
    <td>
      mod
    </td>
    
    <td>
      Same as div, except compute (A mod B), treating A and B as unsigned integers.
    </td>
    
    <td>
      4
    </td>
  </tr>
  
  <tr>
    <td>
      0x07
    </td>
    
    <td>
      smod
    </td>
    
    <td>
      Same as sdiv, except compute (A mod B), treating A and B as signed integers, rather than doing integer divide. The result is defined to be equal to sgn(A)\*(abs(A)%abs(B)), where sgn(x) is 1,0, or -1, if x is positive, zero, or negative, respectively, and abs is absolute value.
    </td>
    
    <td>
      7
    </td>
  </tr>
  
  <tr>
    <td>
      0x08
    </td>
    
    <td>
      addmod
    </td>
    
    <td>
      Pop three values (A, B, C) off the Data Stack. If A, B, and C are all Integers, and C is not zero, Treating A, B, and C as unsigned integers, Push the value (A+B) % C (calculated without 256-bit truncation until end) onto the Data Stack. Otherwise, raise an Error.
    </td>
    
    <td>
      4
    </td>
  </tr>
  
  <tr>
    <td>
      0x09
    </td>
    
    <td>
      mulmod
    </td>
    
    <td>
      Same as addmod, except multiply rather than add.
    </td>
    
    <td>
      4
    </td>
  </tr>
  
  <tr>
    <td>
      0x0a
    </td>
    
    <td>
      exp
    </td>
    
    <td>
      Same as add, except exponentiate rather than add.
    </td>
    
    <td>
      25
    </td>
  </tr>
  
  <tr>
    <td>
      0x0b
    </td>
    
    <td>
      signextend
    </td>
    
    <td>
      Pop two values (A, B) off the Data Stack. If A and B are both Integers, (if A<31 (interpreting A as unsigned), sign extend B from (A + 1) \* 8 bits to 256 bits and Push the result onto the Data Stack; otherwise push A onto the Data Stack). Otherwise, raise an Error.
    </td>
    
    <td>
      7
    </td>
  </tr>
  
  <tr>
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      10s: Comparison & Bitwise Logic Operations
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      0x10
    </td>
    
    <td>
      lt
    </td>
    
    <td>
      Pop two values (A,B) off the Data Stack. If A and B are both Integers, then (treating A and B as unsigned integers, if A<B, push 1 on the Data Stack; otherwise push 0 on the Data Stack). Otherwise, raise an Error.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | 2                         | | 0x11                                            | gt            | Same as lt, except greater than rather than less than                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | 2                         | | 0x12                                            | slt           | Pop two values (A,B) off the Data Stack. If A and B are both Integers, then (treating A and B as signed integers, if A<B, push 1 on the Data Stack; otherwise push 0 on the Data Stack). Otherwise, raise an Error.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | 2                         | | 0x13                                            | sgt           | Same as slt, except greater than rather than less than                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | 2                         | | 0x14                                            | eq            | Pop two values (A, B) off the Data Stack. If A and B have different types, raise an Error. Otherwise if A and B are equal by value, Push 1 on the Data Stack. (Two Tuples are equal by value if they have the same number of slots and are equal by value in every slot.) Otherwise, Push 0 on the Data Stack.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | 2                         | | 0x15                                            | iszero        | If A is the Integer 0, push 1 onto the Data Stack. Otherwise, if A is a non-zero Integer, push 0 onto the Data Stack. Otherwise (i.e., if A is not an Integer), raise an Error.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | 1                         | | 0x16                                            | and           | Pop two values (A, B) off the Data Stack. If A and B are both Integers, then push the bitwise and of A and B on the Data Stack. Otherwise, raise an Error.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | 2                         | | 0x17                                            | or            | Same as and, except bitwise or rather than bitwise and                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | 2                         | | 0x18                                            | xor           | Same as and, except bitwise xor rather than bitwise and                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | 2                         | | 0x19                                            | not           | Pop one value (A) off the Data Stack. If A is an Integer, then push the bitwise negation of A on the Data Stack. Otherwise, raise an Error.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | 1                         | | 0x1a                                            | byte          | Pop two values (A, B) off the Data Stack. If A and B are both Integers, (if A<32 (interpreting A as unsigned), then push the A’th byte of B onto Data Stack, otherwise Integer 0 Stack). Otherwise, raise an Error. | 4 | | 0x1b shl Pop two values (A, B) off Stack. If and are both Integers, shifted left by bits. 0x1c shr right 0x1d sar shift bits with sign extension. &nbsp; 20s: Hashing 0x20 hash a Value (A) Push Hash(A) 7 0x21 type is Integer, if Codepoint, 1 Tuple, 3 Otherwise (A Buffer), 12 0x22 ethhash2 Values (A,B) convert (big-endian) each into length-32 arrays, concatenate 64-byte array, compute Ethereum that byte-array, result (big-endian), resulting 8 0x23 keccakf Tuple containing seven apply `keccakf` function, defined below, (which will be Integers) 600 0x24 sha256f three B, C) A, C all `sha256f` Integer) 250 30s: Memory, Storage Flow Operations 0x30 pop one value discard value. 0x31 spush copy Static 0x32 rpush Register 0x33 rset Set to A. 2 0x34 jump set Instruction Stack 0x35 cjump not Codepoint or (If zero, do Nothing. A.). 0x36 stackempty empty, on 0x37 pcpush currently executing operation 0x38 auxpush it Aux 0x39 auxpop 0x3a auxstackempty 0x3b nop Do nothing. 0x3c errpush Error 0x3d errset 40s: Duplication Exchange 0x40 dup0 0x41 dup1 B,A,B in order. 0x42 dup2 (A,B,C) C,B,A,C 0x43 swap1 0x44 swap2 data A,B,C 50s: 0x50 tget integer, x-bt =1>=0 and A is less than length(B), then Push the value in the A_th slot of B onto the Data Stack. Otherwise raise an Error.
    </td>
    
    <td>
      2
    </td>
  </tr>
  
  <tr>
    <td>
      0x51
    </td>
    
    <td>
      tset
    </td>
    
    <td>
      Pop three values (A,B,C) off of the Data Stack. If B is a Tuple, and A is an Integer, and A>=0, and A is less than length(B), then create a new Tuple that is identical to B, except that slot A has been set to C, then Push the new Tuple onto the Data Stack. Otherwise, raise an Error.
    </td>
    
    <td>
      40
    </td>
  </tr>
  
  <tr>
    <td>
      0x52
    </td>
    
    <td>
      tlen
    </td>
    
    <td>
      Pop a value (A) off the Data Stack. If A is a Tuple, push the length of A (i.e. the number of slots in A) onto the Data Stack. Otherwise, raise an Error.
    </td>
    
    <td>
      2
    </td>
  </tr>
  
  <tr>
    <td>
      0x53
    </td>
    
    <td>
      xget
    </td>
    
    <td>
      Pop one value (A) off the Data Stack and one value (B) off the Aux Stack. If B is a Tuple, and A is an integer, and A>=0 and A is less than length(B), then Push the value in the A_th slot of B onto the Data Stack and push B back onto the Aux Stack. Otherwise raise an Error.
    </td>
    
    <td>
      3
    </td>
  </tr>
  
  <tr>
    <td>
      0x54
    </td>
    
    <td>
      xset
    </td>
    
    <td>
      Pop three values (A,B) off of the Data Stack and one value (C) off the Aux Stack. If C is a Tuple, and A is an Integer, and A>=0, and A is less than length(C), then create a new Tuple that is identical to C, except that slot A has been set to B, then Push the new Tuple onto the Aux Stack. Otherwise, raise an Error.
    </td>
    
    <td>
      41
    </td>
  </tr>
  
  <tr>
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      60s: Logging Operations
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      0x60
    </td>
    
    <td>
      breakpoint
    </td>
    
    <td>
      In an AVM emulator, return control to the Runtime Environment.
    </td>
    
    <td>
      100
    </td>
  </tr>
  
  <tr>
    <td>
      0x61
    </td>
    
    <td>
      log
    </td>
    
    <td>
      Pop a Value (A) off the Data Stack, and convey A to the Runtime Environment as a log event.
    </td>
    
    <td>
      100
    </td>
  </tr>
  
  <tr>
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      70s: System operations
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      0x70
    </td>
    
    <td>
      send
    </td>
    
    <td>
      Pop two values (A,B) off the Data Stack. If A is not an integer, B is not a buffer, the length of B is greater than A, A is greater than SEND_SIZE_LIMIT, or A is zero, raise an error. Otherwise, tell the Runtime Environment to publish B extended to length A with zeroes as an outgoing message of this VM.
    </td>
    
    <td>
      100
    </td>
  </tr>
  
  <tr>
    <td>
      0x71
    </td>
    
    <td>
      inboxpeek
    </td>
    
    <td>
      Pop a Value (A) off the Data Stack. If A is not an integer, raise an Error. Otherwise if the Pending Message is the empty Tuple then (block until the VM's inbox sequence is non-empty, then remove the first item from the inbox sequence as supplied by the Runtime Environment and set the Pending Message equal to it). Then if A equals the second value in the Pending Message Tuple, Push 1 onto the Data Stack, otherwise push 0 onto the Data Stack.
    </td>
    
    <td>
      40
    </td>
  </tr>
  
  <tr>
    <td>
      0x72
    </td>
    
    <td>
      inbox
    </td>
    
    <td>
      If the Pending Message is not the empty Tuple, push the Pending Message onto the Data Stack and then set the Pending Message equal to the empty Tuple. Otherwise, block until the VM's inbox sequence is non-empty. Then remove the first item from the inbox sequence as supplied by the Runtime Environment and push the result onto the Data Stack.
    </td>
    
    <td>
      40
    </td>
  </tr>
  
  <tr>
    <td>
      0x73
    </td>
    
    <td>
      error
    </td>
    
    <td>
      Raise an Error.
    </td>
    
    <td>
      5
    </td>
  </tr>
  
  <tr>
    <td>
      0x74
    </td>
    
    <td>
      halt
    </td>
    
    <td>
      Enter the Halted state.
    </td>
    
    <td>
      10
    </td>
  </tr>
  
  <tr>
    <td>
      0x75
    </td>
    
    <td>
      setgas
    </td>
    
    <td>
      Pop a Value (A) off of the Data Stack. If A is an Integer, write A to the AVMGasRemaining register. Otherwise, raise an Error.
    </td>
    
    <td>
      1
    </td>
  </tr>
  
  <tr>
    <td>
      0x76
    </td>
    
    <td>
      pushgas
    </td>
    
    <td>
      Push the current value of AVMGasRemaining onto the Data Stack.
    </td>
    
    <td>
      1
    </td>
  </tr>
  
  <tr>
    <td>
      0x77
    </td>
    
    <td>
      errcodepoint
    </td>
    
    <td>
      Push the error code point to the data stack.
    </td>
    
    <td>
      25
    </td>
  </tr>
  
  <tr>
    <td>
      0x78
    </td>
    
    <td>
      pushinsn
    </td>
    
    <td>
      Pop two values (A,B) off the Data Stack. If A is an integer and B is a CodePoint, push a new CodePoint to the Data Stack with opcode A and next CodePoint B. Otherwise raise an Error.
    </td>
    
    <td>
      25
    </td>
  </tr>
  
  <tr>
    <td>
      0x79
    </td>
    
    <td>
      pushinsnimm
    </td>
    
    <td>
      Pop three values (A,B, C) off the Data Stack. If A is an integer and C is a CodePoint, push a new CodePoint to the Data Stack with opcode A, immediate B, and next CodePoint C. Otherwise raise an Error.
    </td>
    
    <td>
      25
    </td>
  </tr>
  
  <tr>
    <td>
      0x7b
    </td>
    
    <td>
      sideload
    </td>
    
    <td>
      Pop a Value (A) of the Data Stake. If A is an Integer, Push an empty tuple to the stack. Otherwise, raise an Error.
    </td>
    
    <td>
      10
    </td>
  </tr>
  
  <tr>
    <td>
      80s: Precompile Operations
    </td>
    
    <td>
    </td>
    
    <td>
      &nbsp;
    </td>
    
    <td>
    </td>
  </tr>
  
  <tr>
    <td>
      0x80
    </td>
    
    <td>
      ecrecover
    </td>
    
    <td>
      Pop four values off the Data Stack. If not all of the values are integers raise an error. The first two values first and second half of a compact ecdsa signature, the third is the recovery ID of the signature, and the forth is the message. If the recovered ethereum address was valid push the address, otherwise push 0. This instruction matches the behavior of the EVM ecrecover opcode, except it expects the recover ID to be a 0 or 1 as opposed to a 27 or 28 in Ethereum.
    </td>
    
    <td>
      20000
    </td>
  </tr>
  
  <tr>
    <td>
      0x81
    </td>
    
    <td>
      ecadd
    </td>
    
    <td>
      Pop four values (A, B, C, D) off the Datastack. This operation adds two points on the alt_bn128 curve. If not all of the values are integers raise an error. A and B are interpreted as the X and Y coordinates of a point from G1, C and D are interpreted as the X and Y coordinates of a second point. The two points are added resulting in a new point, R. The y coordinate of R is pushed to the Datastack, then the X coordinate or R is pushed to the Datastack.
    </td>
    
    <td>
      3500
    </td>
  </tr>
  
  <tr>
    <td>
      0x82
    </td>
    
    <td>
      ecmul
    </td>
    
    <td>
      Pop three values (A, B, C) off the Datastack. This operation multiplies a point by a scalar on the alt_bn128 curve. If not all of the values are integers raise an error. A and B are interpreted as the X and Y coordinates of a point from G1, C is interpreted as a scalar. The point is multiplied by the scalar resulting in a new point, R. The y coordinate of R is pushed to the Datastack, then the X coordinate or R is pushed to the Datastack.
    </td>
    
    <td>
      82000
    </td>
  </tr>
  
  <tr>
    <td>
      0x83
    </td>
    
    <td>
      ecpairing
    </td>
    
    <td>
      Pop a value (A) off the Datastack.The Value A is interpreted as a nested stack of 2-Tuples where the first member is a Value and the second member is either a 2-Tuple or and empty Tuple signaling the termination of the stack. If A does not have that form, or there were more than 30 values in the stack, or not all values in the stack were 6-Tuples containing all integers, raise an error. The number of items extracted from the Tuple stack is k. The first and second Tuple elements are the X and Y coordinates of a G1 point, the third and fourth elements are interpreted as the two parts of the X coordinate of a G2 point and the fifth and sixth elements are interpreted as the two parts of the Y coordinate of the G2 point. The alt_bn128 pairing operation is applied to that list of points, and a push a 1 to the Datastack if the result is the one point on alt_bn128, push 0 otherwise.
    </td>
    
    <td>
      1000 + 500000\*min(k, 30)
    </td>
  </tr>
  
  <tr>
    <td>
      0xa0
    </td>
    
    <td>
      newbuffer
    </td>
    
    <td>
      Push an empty buffer to stack
    </td>
    
    <td>
      10
    </td>
  </tr>
  
  <tr>
    <td>
      0xa1
    </td>
    
    <td>
      getbuffer8
    </td>
    
    <td>
      Pop two values (A) and (B) off the stack. The value A must be a buffer and B must be an integer smaller than 2\*\*64. If any of these conditions are not met, raise an error. Pushes to the stack Bth byte of buffer A.
    </td>
    
    <td>
      10
    </td>
  </tr>
  
  <tr>
    <td>
      0xa2
    </td>
    
    <td>
      getbuffer64
    </td>
    
    <td>
      Pop two values (A) and (B) off the stack. The value A must be a buffer and B must be an integer smaller than 2\*\*64-7. If any of these conditions are not met, raise an error. Pushes to the stack B..B+7 bytes of buffer A as BE integer.
    </td>
    
    <td>
      10
    </td>
  </tr>
  
  <tr>
    <td>
      0xa3
    </td>
    
    <td>
      getbuffer256
    </td>
    
    <td>
      Pop two values (A) and (B) off the stack. The value A must be a buffer and B must be an integer smaller than 2\*\*64-31. If any of these conditions are not met, raise an error. Pushes to the stack B..B+31 bytes of buffer A as BE integer.
    </td>
    
    <td>
      10
    </td>
  </tr>
  
  <tr>
    <td>
      0xa4
    </td>
    
    <td>
      setbuffer8
    </td>
    
    <td>
      Pop three values (A), (B) and (C) off the stack. The value A must be a buffer, B must be an integer smaller than 2<strong x-id="1">64 and C must be an integer smaller than 2</strong>8. If any of these conditions are not met, raise an error. Pushes to stack a new buffer that is same as A except that byte in position B is now C.
    </td>
    
    <td>
      100
    </td>
  </tr>
  
  <tr>
    <td>
      0xa5
    </td>
    
    <td>
      setbuffer64
    </td>
    
    <td>
      Pop three values (A), (B) and (C) off the stack. The value A must be a buffer, B must be an integer smaller than 2<strong x-id="1">64-7 and C must be an integer smaller than 2</strong>64. If any of these conditions are not met, raise an error. Pushes to stack a new buffer that is same as A except that bytes in positions B..B+7 are now BE representation of C.
    </td>
    
    <td>
      100
    </td>
  </tr>
  
  <tr>
    <td>
      0xa6
    </td>
    
    <td>
      setbuffer256
    </td>
    
    <td>
      Pop three values (A), (B) and (C) off the stack. The value A must be a buffer, B must be an integer smaller than 2\*\*64-31 and C must be an integer. If any of these conditions are not met, raise an error. Pushes to stack a new buffer that is same as A except that bytes in positions B..B+31 are now BE representation of C.
    </td>
    
    <td>
      100
    </td>
  </tr>
</table>

### Definition of `keccakf`

The `keccakf` function is computed by the the `keccakf` instruction. The function takes an array of seven Integers as input, and produces an array of seven Integers as output.

The function carries out three steps.

1. Using the input array of seven Integers, derive a 200-byte string. For i = 0 through 5 inclusive, bytes _32i_ through _32i+31_ of the result are set equal to the 32-byte big-endian representation of _input[i]_. Bytes 192-199 of the result are set equal to the 8-byte big-endian representation _input[6] % (2\*\*64)_.
2. Using the result of the Step 1 as input, compute the function KECCAK-p[1600, 24] as defined in the SHA-3 standard (FIPS PUB 202, dated August 2015), producing a 200-byte string as output.
3. Using the result of Step 2 is input, derive an output array of seven Integers. This array is the result produced by the `keccakf`instruction. For i = 0 through 5 inclusive, _output[i]_ is set equal to bytes _32i_ through _32i+31_ of the result of Step 2 (interpreted as a 32-byte big-endian Integer). output[6] is set equal to bytes 192-199 of the result of Step 2 (interpreted as an 8-byte big-endian Integer in the range 0 through _(2\*\*64)-1)_).

### Definition of `sha256f`

The `sha256f` function is computed by the `sha256f` instruction. The function takes 3 Integers as input, and produces, and produces an Integer as output.

The function carries out three steps.

1. The 32 byte little-endian representation of the first item from the stack is interpreted as the digest and the 32 byte representations of the second and third items from the stack are concatenated and interpreted as the input array.
2. Using the digest and input array from Step 1, compute the SHA256 compression function, producing a 32 byte string as output
3. Using the result of Step 2 as input, derive an Integer from the little-endian interpretation of the output
