// SPDX-License-Identifier: MIT

pragma solidity >=0.8.13 <0.9.0;

import "@fhenixprotocol/contracts/FHE.sol";

contract SortedList {
    uint8 internal constant SIZE_LIMIT = 254;
    uint8 internal constant MAX_UINT8 = type(uint8).max;
    uint32 internal constant MAX_UINT32 = type(uint32).max;

    struct ownedValue {
        address owner;
        euint32 val;
    }

    // Length of the sorted list, public for debugging, internal for production
    uint8 internal dataSize;

    // The relative indices of all the value in the database, public for debugging, internal for production
    euint32[SIZE_LIMIT] internal relativeIdx;

    // The database as mapping, public for debugging, internal for production
    mapping (euint32 => ownedValue) internal data;

    address public admin;

    constructor()
    {
        admin = msg.sender;
        // Insert the lower and upper bound (min and max value of uint32) to the database
        euint32 minRelativeIdx = FHE.asEuint32(0);
        relativeIdx[0] = minRelativeIdx;
        data[minRelativeIdx] = ownedValue({
            owner: admin,
            val: FHE.asEuint32(0)
        });
        euint32 maxRelativeIdx = FHE.asEuint32(MAX_UINT32);
        relativeIdx[1] = maxRelativeIdx;
        data[maxRelativeIdx] = ownedValue({
            owner: admin,
            val: FHE.asEuint32(MAX_UINT32)
        });
        dataSize = 2;
    }

    function _toUint32(int32 val) internal pure returns (uint32)
    {
        if (val == type(int32).min)
            return uint32(0);
        else if (val < 0)
            return uint32(2) ** 31 - uint32(-val);
        else
            return uint32(2) ** 31 + uint32(val);
    }

    /*
     * Positioning a value in the sorted list
     * Returns the following encrypted outputs:
     *   [uint32 seat] as the relative index of the value in the sorted list, for potential insertion
     *   [uint8 pos] as the absolute index of the value in the sorted list
     *   [bool existed] as whether the value occurs in the list
     *   [bool occupied] as whether there is a congestion of relative indices at the insertion point
     */
    function position(euint32 val) internal view returns (euint32, euint8, ebool, ebool)
    {
        euint32 leftBoundIdx = FHE.asEuint32(0);
        euint32 rightBoundIdx = FHE.asEuint32(MAX_UINT32);
        euint8 pos = FHE.asEuint8(0);
        ebool existed = FHE.asEbool(false);
        for (uint8 i=0; i<dataSize; ++i) {
            euint32 _idx = relativeIdx[i];
            euint32 _val = data[_idx].val;
            leftBoundIdx = FHE.select(FHE.and(_val.lt(val), _idx.gt(leftBoundIdx)), _idx, leftBoundIdx);
            pos = FHE.select(_val.lt(val), pos + FHE.asEuint8(1), pos);
            rightBoundIdx = FHE.select(FHE.and(_val.gte(val), _idx.lt(rightBoundIdx)), _idx, rightBoundIdx);
            existed = FHE.select(_val.eq(val), FHE.asEbool(true), existed);
        }
        euint32 seat = FHE.shr(FHE.add(leftBoundIdx, rightBoundIdx), FHE.asEuint32(1));
        return (seat, pos, existed, rightBoundIdx.eq(leftBoundIdx + FHE.asEuint32(1)));
    }

    /*
     * Relabelling when congestion of relative indices found at a insertion point
     * Currently using the naive approach: sorting the whole list and recalculate the relative indices
     */
    function relabel(euint32 val) internal returns (euint32)
    {
        euint32 v0;
        euint32 v1;
        for (uint8 i=0; i<dataSize; ++i)
            for (uint8 j=i+1; j<dataSize; ++j) {
                v0 = FHE.min(relativeIdx[i], relativeIdx[j]);
                v1 = FHE.max(relativeIdx[i], relativeIdx[j]);
                relativeIdx[i] = v0;
                relativeIdx[j] = v1;
            }
        euint32 gap = FHE.div(relativeIdx[dataSize - 1] - relativeIdx[0], FHE.asEuint32(uint32(dataSize - 1)));
        v0 = relativeIdx[0];
        ownedValue memory z0;
        for (uint8 i=1; i+1<dataSize; ++i) {
            z0 = data[relativeIdx[i]];
            v0 = v0 + gap;
            delete data[relativeIdx[i]];
            relativeIdx[i] = v0;
            data[v0] = z0;
        }
        euint32 seat;
        (seat, , ,) = position(val);
        return seat;
    }

    /*
     * Insert a new value to the sorted list, returns the absolute inserted index
     */
    function _insert(euint32 val) internal returns (euint8)
    {
        euint8 pos;
        euint32 seat;
        ebool occupied;
        (seat, pos, , occupied) = position(val);
        seat = FHE.select(occupied, relabel(val), seat);
        relativeIdx[dataSize++] = seat;
        data[seat] = ownedValue({
            owner: msg.sender,
            val: val
        });
        return pos;
    }

    function insert(int32 newVal) external returns (uint8, string memory)
    {
        if (dataSize == SIZE_LIMIT)
            return (MAX_UINT8, "Size of the database reaches limit");
        else {
            uint32 uNewVal = _toUint32(newVal);
            if (uNewVal == 0 || uNewVal == MAX_UINT32)
                return (MAX_UINT8, "Not allowed to insert a value of lower or upper bound of 32-bit integer");
            else
                return (FHE.decrypt(_insert(FHE.asEuint32(uNewVal))), "Inserted");
        }
    }

    /*
     * Find a value in the sorted list, returns the absolute inserted index of the value, or MAX_UINT8 if not found
     */
    function _find(euint32 val) internal view returns (euint8)
    {
        euint8 pos;
        ebool existed;
        (, pos, existed, ) = position(val);
        return FHE.select(existed, pos, FHE.asEuint8(MAX_UINT8));
    }

    function find(int32 val) external view returns (uint8, string memory)
    {
        uint32 uVal = _toUint32(val);
        if (uVal == 0 || uVal == MAX_UINT32)
            return (MAX_UINT8, "Not allowed to find a value of lower or upper bound of 32-bit integer");
        else {
            uint8 pos = FHE.decrypt(_find(FHE.asEuint32(uVal)));
            if (pos == MAX_UINT8) 
                return (pos, "Not found");
            else
                return (pos, "Found");
        }
    }

    /*
     * Here shows a bug in the FHE.sol library
     * After the encrypted FHE.asEuint32(MAX_UINT32) as a returning value, it is not decrypted to MAX_UINT32 but some other value 
    function _untested_find(euint32 val) internal view returns (euint32)
    {
        euint8 pos;
        ebool existed;
        (, pos, existed, ) = position(val);
        return FHE.select(existed, FHE.asEuint32(uint32(1)), FHE.asEuint32(MAX_UINT32));
    }

    function untested_find(int32 val) external view returns (uint32, string memory)
    {
        uint32 uVal = _toUint32(val);
        if (uVal == 0 || uVal == MAX_UINT32)
            return (MAX_UINT32, "Not allowed to find a value of lower or upper bound of 32-bit integer");
        else {
            uint32 pos = FHE.decrypt(_untested_find(FHE.asEuint32(uVal)));
            if (pos == MAX_UINT32) 
                return (pos, "Not found");
            else
                return (pos, "Found");
        }
    }
    */
    

    /*
     * Delete a value in the sorted list, returns the absolute inserted index of the value before deletion, or MAX_UINT8 if not found
     * For duplicate element of the same value found in the list, only one of them will be deleted
     * Another bug found in the FHE.sol library, the transaction crashes when using FHE.and(ebool, ebool) here
     */
    function _erase(euint32 val) internal returns (euint32, euint8, ebool)
    {
        euint32 emptySeat = FHE.asEuint32(MAX_UINT32);
        euint8 pos = FHE.asEuint8(0);
        ebool notErased = FHE.asEbool(true);
        for (uint8 i=0; i<dataSize; ++i) {
            euint32 _idx = relativeIdx[i];
            //euint32 _val = data[_idx].val;
            // To avoid FHE.and, enable the next line instead of the previous line
            euint32 _val = FHE.select(notErased, data[_idx].val, data[_idx].val + FHE.asEuint32(1));
            pos = FHE.select(_val.lt(val), pos + FHE.asEuint8(1), pos);
            if (data[_idx].owner == msg.sender) {
                // Transaction crashes when using FHE.and for two ebools
                //ebool eraseIt = FHE.and(notErased, _val.eq(val));
                // Here works well
                ebool eraseIt = _val.eq(val);
                relativeIdx[i] = FHE.select(eraseIt, relativeIdx[dataSize - 1], relativeIdx[i]);
                emptySeat = FHE.select(eraseIt, _idx, emptySeat);
                notErased = FHE.select(eraseIt, FHE.asEbool(false), notErased);
            }
        }
        return (emptySeat, pos, notErased);
    }

    function erase(int32 val) external returns (uint8, string memory)
    {
        uint32 uVal = _toUint32(val);
        if (uVal == 0 || uVal == MAX_UINT32)
            return (MAX_UINT8, "Not allowed to erase a value of lower or upper bound of 32-bit integer");
        else {
            euint32 emptySeat;
            euint8 encryptedPos;
            ebool encryptedNotErased;
            (emptySeat, encryptedPos, encryptedNotErased) = _erase(FHE.asEuint32(uVal));
            if (FHE.decrypt(encryptedNotErased))
                return (MAX_UINT8, "No owned data with correct value found");
            else {
                delete data[emptySeat];
                dataSize--;
                return (FHE.decrypt(encryptedPos), "Erased");
            }
        }
    }
}

