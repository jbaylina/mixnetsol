contract ECCurve {
  function publicKey(uint256 privKey) constant
    returns(uint256 qx, uint256 qy);
  function deriveKey(uint256 privKey, uint256 pubX, uint256 pubY) constant
    returns(uint256 qx, uint256 qy);
}

contract MixNet {
    uint constant depositValue=100;
    uint constant fee= 10;

    uint constant ST_DEPOSITING = 0;
    uint constant ST_MIXING = 1;
    uint constant ST_VALIDATING = 2;
    uint constant ST_TERMINATING = 3;

    uint constant TIMEOUT_DEPOSITING = 1 hours;
    uint constant TIMEOUT_MIXING = 1 hours;
    uint constant TIMEOUT_VALIDATING = 1 hours;

    uint constant NUsers = 5;
    uint constant NSlots = 25;
    uint constant NSlotsPerUser = 5;

    ECCurve ec;


    uint constant D160 = 0x10000000000000000000000000000000000000000;

    uint state;
    uint stateDate;
    uint pendingUsers;
    uint blockClosed;

    struct UserState {
        uint pubX;
        uint pubY;
        bytes32 hashData;

// For Validation state
        bytes32[] mask;
        uint privKey;
        address dest;
        uint validationState;
        bool validated;


// Termination state
        uint pending;
    }

    UserState[] userStates;

    mapping(address => uint) userStateIdx; // Index Relative to 1 in userStates


    bytes32[] board;

    address[] destAddrs;


    address owner;


    function MixNet() {
        state = ST_DEPOSITING;
        stateDate = now;
        pendingUsers = NUsers;
        board.length = NSlots * 2;
        owner = msg.sender;
        ec = ECCurve(0x0);
    }



    function deposit(uint pubX, uint pubY) {
        uint idx = userStateIdx[msg.sender];

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
        userStateIdx[msg.sender] = userStates.length;

        userState.pubX = pubX;
        userState.pubY = pubY;

        pendingUsers --;


        if (pendingUsers == 0) {
            state = ST_MIXING;
            pendingUsers = NUsers;
            stateDate = now;
            blockClosed = block.number;
        }
    }

    function mix(bytes32[] data) {
        uint i;
        uint idx = userStateIdx[msg.sender];

        if (idx == 0)
            throw;
        if (now > stateDate + TIMEOUT_MIXING)
            throw;
        if (state != ST_DEPOSITING)
            throw;
        if (data.length != board.length)
            throw;

        UserState userState = userStates[idx-1];

        if (userState.hashData != 0)
            throw;

        pendingUsers --;
        userState.hashData = sha3(data);

        for (i=0; i< data.length; i++) {
            board[i] = board[i] ^ data[i];
        }

        // The last one pay the party.
        // So this is an incentive to be fast
        if (pendingUsers == 0) {
            validateBoardAndPay();
        }
    }

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

    function getByte(uint data, uint p) internal returns (uint) {
        uint pos = (2 ** (p*8));
        uint mask = 0xFF * pos;
        uint res = (data & mask) / pos;
        return res;
    }

    function setByte(uint data, uint p, byte v) internal returns (uint) {
        uint pos = (2 ** (p*8));
        uint res = res | (uint(v) * pos);
        return res;
    }

    function boardIsZero() internal returns(bool) {
        uint i;
        for (i=0; i<board.length; i++) {
            if (board[i] != 0) return false;
        }
        return true;
    }

    function payAll() internal returns(bool) {
        uint i;
        for (i=0; i<destAddrs.length; i++) {
            destAddrs[i].send(depositValue);
        }
    }

    function validate(uint privKey, address dest) {
        uint idx = userStateIdx[msg.sender];
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
            idx = (userState.validationState <= idx) ? userState.validationState-1 : userState.validationState;
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
            uint d = calcDataHash(userState.privKey, getSeed(), dest);
            for (i=0; i<NSlotsPerUser; i++) {
                uint slot = getByte(d, 31-i);
                userState.mask[i*2] ^= bytes32(d);
                userState.mask[i*2+1] ^= sha3(d);
            }
            if ( sha3(userState.mask)  != userState.hashData)
                throw;
            userState.validationState ++;
            userState.validated = true;
            if (!msg.sender.send(depositValue)) {
                throw;
            }
        }
    }

    function calcDataHash(uint privKey, bytes32 seed, address dest) constant returns (uint) {
        byte[] pos ;
        uint i;
        uint res = uint(dest);
        bytes32 prnd;

        pos.length = NSlots;
        for (i=0; i<NSlots; i++) pos[i] = byte(i);

        prnd = sha3(privKey ^ uint(seed));
        for (i=0; i<NSlotsPerUser; i++) {
            uint p = uint(prnd) % (NSlots - i);
            res = setByte(res, 31-i, pos[p]);
            pos[p] = pos[ pos.length -1];
            pos.length--;
            prnd = sha3(prnd);
        }

        return res;
    }

    function getSeed() constant returns (bytes32) {
        return block.blockhash(blockClosed);
    }

    function teminate() {
        if (   (state == ST_DEPOSITING)
            && (now > stateDate + TIMEOUT_DEPOSITING))
            timeoutDeposit();
        if (   (state == ST_MIXING)
            && (now > stateDate + TIMEOUT_MIXING))
            timeoutMixing();
        if (   (state == ST_VALIDATING)
            && (now > stateDate + TIMEOUT_VALIDATING))
            timeoutValidating();

        uint idx = userStateIdx[msg.sender];

        if (idx == 0)
            throw;
        if (state != ST_TERMINATING)
            throw;

        UserState userState = userStates[idx-1];

        uint amount = userState.pending;
        userState.pending =0;

        if (!msg.sender.send(amount)) {
            throw;
        }

        pendingUsers --;

        if (pendingUsers == 0) {
            suicide(owner);
        }
    }

    function timeoutDeposit() internal {
        uint i;
        for (i=0; i<userStates.length; i++ ) {
            userStates[i].pending = depositValue;
        }
        pendingUsers = userStates.length;
        state = ST_TERMINATING;
        stateDate = now;
    }

    function timeoutMixing() internal {
        uint i;
        uint bad =0;
        UserState userState;
        for (i=0; i<NUsers; i++) {
            userState= userStates[i];
            if (userState.hashData == 0) bad++;
        }
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

        state = ST_TERMINATING;
        stateDate = now;
    }

    function timeoutValidating() internal {
        uint i;
        uint bad =0;
        UserState userState;
        for (i=0; i<NUsers; i++) {
            userState= userStates[i];
            if (!userState.validated) bad++;
        }
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

        state = ST_TERMINATING;
        stateDate = now;
    }
}
