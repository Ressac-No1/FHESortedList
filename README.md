# FHESortedList

A just-for-testing project done at ZK Hack Kraków.

## Overview
This project uses the Fhenix FHE.sol library to build a very simple database maintaining a sorted list of 32-bit unsigned integers. The Solidity contract provides APIs for insertion, deletion and searching a value in the list.

Two critical bugs in the FHE.sol library were detected while testing this project.

## Details
It uses **relative indices** in the maintenance of a dynamic sorted list. For a list of length *n*, in addition to the absolute indices [*0..n-1*] indicating the ordering of every values after the list gets sorted, it also arranges a relative index for every value in the list, which can be an arbitrary and unique integer, only to ensure that a value *x* has a smaller relative index than a value *y* if *x<y*. After introducing relative indices, it becomes easier to maintain the ordering of a dynamic sorted list with the help of **Dynamic Labelling** implemented by some advanced data structures.

In practice, due to the gas limit of the FHE.sol library, it only supports a short sorted list and it is not feasible to build any advanced data structure on FHE.sol. Therefore, in the project the maintenance of the sorted list and relative indices of elements is done in a brute-force manner, in which the whole list gets manually sorted and all the relative indices are recalculated with balanced gaps in case of a congestion of the relative index at the insertion points occurs.

## Bugs and challenges
The Fhenix FHE.sol library is still under construction and some unpredicted bugs were also detected during the development and testing of this project. There are two major bug of the library found.
- Sometimes the ciphertest of the maximum value of uint32 (2^32-1) is not correctly decrypted to the origin value, but a value a bit smaller than 2^32-1
- The FHE.and operation of two ebools, which expects to return the and result of two booleans under FHE, crashes in transactions

Besides the bugs, the limitation of the FHE.sol library also restricts the scalability of projects developed on it. For instance, the values capable to be encrypted by FHE.sol are most 32-bit integers, but a dynamic labelling algorithm usually requires a much larger space of relative indices to ensure its robustness and efficiency. Another restriction due to the FHE.sol library is that it has yet supported a universal if-else statement, and a branch statement can only be implemented via a ternary assignment operation.

After this hackathon, I (the author) may launch a further project to dive deeply in the FHE.sol library to fix the internal bugs and aim to extend its scalability by introducing more operations.

