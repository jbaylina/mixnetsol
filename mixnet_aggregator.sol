
import "mixnet.sol";

contract MixNetAggregator {

    MixNet[] mixNets;
    mapping(uint => uint) public mixNetIdx;


    function MixNetAggregator() {
        mixNets.length=16;
        mixNetIdx[10 finney] = 1;
        mixNetIdx[20 finney] = 2;
        mixNetIdx[100 finney] = 3;
        mixNetIdx[200 finney] = 4;
        mixNetIdx[500 finney] = 5;
        mixNetIdx[1 ether] = 6;
        mixNetIdx[2 ether] = 7;
        mixNetIdx[5 ether] = 8;
        mixNetIdx[10 ether] = 9;
        mixNetIdx[20 ether] = 10;
        mixNetIdx[50 ether] = 11;
        mixNetIdx[100 ether] = 12;
        mixNetIdx[200 ether] = 13;
        mixNetIdx[500 ether] = 14;
        mixNetIdx[1000 ether] = 15;
    }

    function start(uint pubX, uint pubY, bytes32 hashRand) payable {
        uint idx = mixNetIdx[msg.value];

        // Only admit valid values
        if (idx == 0) throw;

        MixNet mixNet = mixNets[idx];

        if ((address(mixNet) == 0) || (mixNet.getState() != 0)) {
            mixNet = new MixNet(msg.value, msg.value/10, 5);
        } else {
            if (mixNet.userStateIdx(msg.sender) > 0) throw;
        }

        mixNet.proxyDeposit.value(msg.value)(msg.sender,pubX, pubY, hashRand);

        Assignment(msg.sender, address(mixNet), msg.value);
    }

    event Assignment(address indexed user, address indexed mixer, uint indexed depositValue);
}
