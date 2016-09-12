pragma solidity ^0.4.0;

contract EC {
  function publicKey(uint256 privKey) constant
    returns(uint256 qx, uint256 qy);
  function deriveKey(uint256 privKey, uint256 pubX, uint256 pubY) constant
    returns(uint256 qx, uint256 qy);
}

contract MixNet {

    uint constant depositValue=10 ether;
    uint constant fee= 1 ether;

    uint constant ST_DEPOSITING = 0;
    uint constant ST_HASHING = 1;
    uint constant ST_MIXING = 2;
    uint constant ST_VALIDATING = 3;
    uint constant ST_TERMINATING = 4;

    uint constant TIMEOUT_DEPOSITING = 1 hours;
    uint constant TIMEOUT_HASHING = 1 hours;
    uint constant TIMEOUT_MIXING = 1 hours;
    uint constant TIMEOUT_VALIDATING = 1 hours;
    uint constant TIMEOUT_TERMINATING = 30 days;


    uint constant NSlotsPerUser = 5;

    uint NUsers;
    uint NSlots;
    EC ec;

    uint constant D160 = 0x10000000000000000000000000000000000000000;
    uint constant ECAddress = 0x0;

    uint state;
    uint stateDate;
    uint pendingUsers;
    uint seed;

    struct UserState {
        uint pubX;
        uint pubY;
// For hashing
        bytes32 hashData;

// For mixing
        bool dataSent;

// Termination state
        uint pending;

// For Validation state
        uint privKey;
        address dest;
        uint validationState;
        bool validated;
        bytes32[] mask;
    }

    UserState[] public userStates;

    mapping(address => uint) userStateIdx; // Index Relative to 1 in userStates


    bytes32[] board;

    address[] destAddrs;


    address owner;

    modifier onlyOwner { if (msg.sender != owner) throw; _; }


    function MixNet() {
        state = ST_DEPOSITING;
        stateDate = now;
        owner = msg.sender;
        ec = EC(ECAddress);
    }



    function depositFrom(address from, uint pubX, uint pubY) internal {
        uint idx = userStateIdx[from];

        if (state != ST_DEPOSITING)
            throw;
        if (msg.value != depositValue)
            throw;
        if (idx != 0)
            throw;
        if (now > stateDate + TIMEOUT_DEPOSITING)
            throw;

        userStates.length ++;
        UserState userState = userStates [userStates.length-1];
        userStateIdx[from] = userStates.length;

        userState.pubX = pubX;
        userState.pubY = pubY;
    }

    function deposit(uint pubX, uint pubY) payable {
        depositFrom(msg.sender, pubX, pubY);
    }

    function proxyDeposit(address from, uint pubX, uint pubY) onlyOwner payable {
        depositFrom(from, pubX, pubY);
    }


    function close() onlyOwner {
        if (state != ST_DEPOSITING)
            throw;
        if (now > stateDate + TIMEOUT_DEPOSITING)
            throw;

        NUsers = userStates.length;
        NSlots = NUsers * NSlotsPerUser;
        state = ST_HASHING;
        pendingUsers = NUsers;
        stateDate = now;
        seed = uint(sha3(now, block.blockhash(block.number-1)));
        board.length = NSlots * 2;
    }

    function setHashFrom(address from, bytes32 hash) internal {
        uint idx = userStateIdx[from];

        if (idx == 0)
            throw;
        if (state != ST_HASHING)
            throw;
        if (now > stateDate + TIMEOUT_HASHING)
            throw;


        UserState userState = userStates[idx-1];

        if (userState.hashData != 0)
            throw;

        userState.hashData = hash;
        pendingUsers --;

        if (pendingUsers == 0) {
            state = ST_MIXING;
            pendingUsers = NUsers;
            stateDate = now;
        }
    }

    function proxySetHash(address from, bytes32 hash) onlyOwner {
        setHashFrom(from, hash);
    }

    function setHash(bytes32 hash) {
        setHashFrom(msg.sender, hash);
    }

    function mixFrom(address from, uint[] data) internal {
        uint i;
        uint idx = userStateIdx[from];


        if (idx == 0)
            throw;
        if (state != ST_MIXING)
            throw;
        if (now > stateDate + TIMEOUT_MIXING)
            throw;
        if (data.length != board.length)
            throw;

        UserState userState = userStates[idx-1];

        if (userState.hashData != sha3(data))
            throw;
        if (userState.dataSent) {
            throw;
        }

        userState.dataSent = true;
        pendingUsers --;

        for (i=0; i< data.length; i++) {
            board[i] = board[i] ^ bytes32(data[i]);
        }

        // The last one pay the party.
        // So this is an incentive to be fast
        if (pendingUsers == 0) {
            validateBoardAndPay();
        }
    }

    function proxyMix(address from, uint[] data) onlyOwner {
        mixFrom(from, data);
    }

    function mix(uint[] data) {
        mixFrom(msg.sender, data);
    }

/*
    uint st1;
    uint st2;
    function debug() constant returns(uint, uint) {
        return (st1,st2);
    }
*/

    function validateBoardAndPay() internal {

        while ( (destAddrs.length<NUsers) && extractNext()) {}

        if (boardIsZero()) {
            payAll();
            suicide(owner);
        } else {
            state = ST_VALIDATING;
            pendingUsers = NUsers;
            stateDate = now;
        }
    }

    function extractNext() internal returns(bool) {
        bool done;
        uint i;
        for (i=0; i<NSlots && !done; i++) {
            bytes32 data = board[i*2];
            bytes32 hash = board[i*2+1];
            if ((data!=0)&&(sha3(data) == hash)) {
                return extractSlot(uint(data), hash);
            }
        }
        return false;
    }

    function extractSlot(uint256 d, bytes32 hash) internal returns (bool) {
        uint i;
        address a = address( d & (D160-1) );
        for (i=0; i< NSlotsPerUser; i++) {
            uint slot = getByte(d, 31-i);
            if (slot > NSlots) return false;
            board[slot*2] = board[slot*2] ^ bytes32(d);
            board[slot*2 + 1] = board[slot*2 +1] ^ hash;
        }
        destAddrs[destAddrs.length ++] = a;
        return true;
    }

    function getBoard(uint i) constant  returns (bytes32) {
        return board[i];
    }

    function getMask(uint idx, uint i) constant  returns (bytes32) {
        UserState userState = userStates[idx];
        return userState.mask[i];
    }

    function getByte(uint data, uint p) internal returns (uint) {
        uint pos = (2 ** (p*8));
        uint mask = 0xFF * pos;
        uint res = (data & mask) / pos;
        return res;
    }

    function setByte(uint data, uint p, byte v) internal returns (uint) {
        uint pos = (2 ** (p*8));
        uint res = data | (uint(v) * pos);
        return res;
    }

    function boardIsZero() internal returns(bool) {
        uint i;
        for (i=0; i<board.length; i++) {
            if (board[i] != 0) {
                return false;
            }
        }
        return true;
    }

    function payAll() internal returns(bool) {
        uint i;
        for (i=0; i<destAddrs.length; i++) {
            if (!destAddrs[i].send(depositValue)) {
                if (!owner.send(depositValue)) {
                    throw;
                }
            }
        }
    }

    function validateFrom(address from, uint privKey, address dest) internal {
        uint idx = userStateIdx[from];
        uint i;

        if (idx == 0)
            throw;
        if (now > stateDate + TIMEOUT_VALIDATING)
            throw;
        if (state != ST_VALIDATING)
            throw;

        UserState userState = userStates[idx-1];


        if (userState.validationState == 0) {
            var (pubX, pubY) = ec.publicKey(privKey);
            if ((pubX != userState.pubX) || ( pubY != userState.pubY)) throw;
            userState.privKey = privKey;
            userState.dest = dest;
            userState.mask.length = board.length;
            userState.validationState ++;
            return;
        } else if (userState.validationState < NUsers) {
            idx = (userState.validationState < idx) ? userState.validationState-1 : userState.validationState;
            UserState otheUser = userStates[idx];
            var (qx, ) = ec.deriveKey(privKey, otheUser.pubX, otheUser.pubY);

            bytes32 h = sha3(qx);
            for (i=0; i<userState.mask.length; i++) {
                userState.mask[i] = userState.mask[i] ^ h;
                h=sha3(h);
            }

            userState.validationState ++;
            return;
        } else if (userState.validationState == NUsers) {
            uint d = calcDataHash(userState.privKey, getSeed(), userState.dest);
            h = sha3(d);
            for (i=0; i<NSlotsPerUser; i++) {
                uint slot = getByte(d, 31-i);
                userState.mask[slot*2] ^= bytes32(d);
                userState.mask[slot*2+1] ^= h;
            }

            if ( sha3(userState.mask)  != userState.hashData)
                throw;

            userState.validationState ++;
            userState.validated = true;
            pendingUsers --;
            if (!from.send(depositValue)) {
                throw;
            }
        }

        if (pendingUsers == 0) {
            suicide(owner);
        }
    }

    function proxyValidateFrom(address from, uint privKey, address dest) onlyOwner {
        validateFrom(from, privKey, dest);
    }

    function validate(uint privKey, address dest) {
        validateFrom(msg.sender, privKey, dest);
    }

    function calcDataHash(uint privKey, uint seed, address dest) constant returns (uint) {
        uint len = NSlots;
        byte[] memory pos = new byte[](len);
        uint i;
        uint res = uint(dest);

        for (i=0; i<len; i++) pos[i] = byte(i);

        bytes32 prnd = sha3(privKey ^ seed);
        for (i=0; i<NSlotsPerUser; i++) {
            uint p = uint(prnd) % len;
            res = setByte(res, 31-i, pos[p]);
            pos[p] = pos[ len -1];
            len--;
            prnd = sha3(prnd);
        }

        return res;
    }

    function getSeed() constant returns (uint) {
        return seed;
    }

    function teminateFrom(address from) internal {
        if (   (state == ST_DEPOSITING)
            && (now > stateDate + TIMEOUT_DEPOSITING))
            timeoutDeposit();
        if (   (state == ST_HASHING)
            && (now > stateDate + TIMEOUT_HASHING))
            timeoutHashing();
        if (   (state == ST_MIXING)
            && (now > stateDate + TIMEOUT_MIXING))
            timeoutMixing();
        if (   (state == ST_VALIDATING)
            && (now > stateDate + TIMEOUT_VALIDATING))
            timeoutValidating();
        if (   (state == ST_TERMINATING)
            && (now > stateDate + TIMEOUT_TERMINATING))
        {
            suicide(owner);
            return;
        }

        uint idx = userStateIdx[from];

        if (idx == 0)
            throw;
        if (state != ST_TERMINATING)
            throw;

        UserState userState = userStates[idx-1];

        uint amount = userState.pending;
        userState.pending =0;

        if (!from.send(amount)) {
            throw;
        }

        pendingUsers --;

        if (pendingUsers == 0) {
            suicide(owner);
        }
    }

    function proxyTeminate(address from) onlyOwner {
        teminateFrom(from);
    }

    function terminate() {
        teminateFrom(msg.sender);
    }

    function timeoutDeposit() internal {
        uint i;
        for (i=0; i<userStates.length; i++ ) {
            userStates[i].pending = depositValue;
        }
        pendingUsers = userStates.length;
        state = ST_TERMINATING;
        stateDate = stateDate + TIMEOUT_DEPOSITING;
    }

    function timeoutHashing() internal {
        uint i;
        uint bad =0;
        for (i=0; i<NUsers; i++) {
            UserState userState= userStates[i];
            if (userState.hashData == 0) bad++;
        }
        if (bad == NUsers) {
            for (i=0; i<NUsers; i++) {
                userState.pending = depositValue;
            }
            pendingUsers = NUsers;
        } else {
            uint extra = (fee * bad) / (NUsers - bad);
            pendingUsers =0;
            for (i=0; i<NUsers; i++) {
                userState= userStates[i];
                if (userState.hashData == 0) {
                    userState.pending = depositValue - fee;
                } else {
                    userState.pending = depositValue + extra;
                }
                if (userState.pending > 0) pendingUsers++;
            }
        }

        state = ST_TERMINATING;
        stateDate = stateDate + TIMEOUT_HASHING;

    }

    function timeoutMixing() internal {
        uint i;
        uint bad =0;
        for (i=0; i<NUsers; i++) {
            UserState userState= userStates[i];
            if (!userState.dataSent) bad++;
        }
        if (bad == NUsers) {
            for (i=0; i<NUsers; i++) {
                userState.pending = depositValue;
            }
            pendingUsers = NUsers;
        } else {
            uint extra = (fee * bad) / (NUsers - bad);
            pendingUsers =0;
            for (i=0; i<NUsers; i++) {
                userState= userStates[i];
                if (!userState.dataSent) {
                    userState.pending = depositValue - fee;
                } else {
                    userState.pending = depositValue + extra;
                }
                if (userState.pending > 0) pendingUsers++;
            }
        }

        state = ST_TERMINATING;
        stateDate = stateDate + TIMEOUT_MIXING;
    }

    function timeoutValidating() internal {
        uint i;
        uint bad =0;
        for (i=0; i<NUsers; i++) {
            UserState userState= userStates[i];
            if (!userState.validated) bad++;
        }
        if (bad == NUsers) {
            for (i=0; i<NUsers; i++) {
                userState.pending = depositValue;
            }
            pendingUsers = NUsers;
        } else {
            uint extra = (fee * bad) / (NUsers - bad);
            pendingUsers =0;
            for (i=0; i<NUsers; i++) {
                userState= userStates[i];
                if (!userState.validated) {
                    userState.pending = depositValue - fee;
                } else {
                    userState.pending = extra;
                }

                if (userState.pending > 0) pendingUsers++;
            }
        }


        state = ST_TERMINATING;
        stateDate = stateDate + TIMEOUT_VALIDATING;
    }

    function getECAddress() constant returns(address) {
        return address(ec);
    }

    function getState() constant returns(uint) {
        if (   (state == ST_DEPOSITING)
            && (now > stateDate + TIMEOUT_DEPOSITING))
            return ST_TERMINATING;
        if (   (state == ST_HASHING)
            && (now > stateDate + TIMEOUT_HASHING))
            return ST_TERMINATING;
        if (   (state == ST_MIXING)
            && (now > stateDate + TIMEOUT_MIXING))
            return ST_TERMINATING;
        if (   (state == ST_VALIDATING)
            && (now > stateDate + TIMEOUT_VALIDATING))
            return ST_TERMINATING;
        return state;
    }

    function getTimeoutDate() constant returns(uint) {
        if (   (state == ST_DEPOSITING)
            && (now > stateDate + TIMEOUT_DEPOSITING))
            return stateDate + TIMEOUT_DEPOSITING;
        if (   (state == ST_HASHING)
            && (now > stateDate + TIMEOUT_HASHING))
            return stateDate + TIMEOUT_HASHING;
        if (   (state == ST_MIXING)
            && (now > stateDate + TIMEOUT_MIXING))
            return stateDate + TIMEOUT_MIXING;
        if (   (state == ST_VALIDATING)
            && (now > stateDate + TIMEOUT_VALIDATING))
            return stateDate + TIMEOUT_VALIDATING;
        return stateDate + TIMEOUT_TERMINATING;
    }

    function getNUsers() constant returns (uint) {
        return userStates.length;
    }

    function getUserPubKey(uint idx) constant returns(uint pubX, uint pubY) {
        return (userStates[idx].pubX, userStates[idx].pubY);
    }
}
