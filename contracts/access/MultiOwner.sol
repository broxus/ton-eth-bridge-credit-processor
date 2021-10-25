pragma ton-solidity >= 0.39.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../../node_modules/@broxus/contracts/contracts/_ErrorCodes.sol";

abstract contract MultiOwner {
    uint[] public owners;

    event OwnerAdded(uint newOwner);

    modifier anyOwner() {
        require(isOwner(), _ErrorCodes.NOT_OWNER);
        _;
    }

    function addOwner(uint newOwner) external anyOwner {
        require(newOwner != 0, _ErrorCodes.ZERO_OWNER);
        tvm.accept();

        owners.push(newOwner);
        emit OwnerAdded(newOwner);
    }

    function isOwner() private returns(bool) {
        for (uint i = 0; i < owners.length; i++) {
            if(owners[i] == msg.pubkey() || owners[i] == msg.sender.value)
            {
                return true;
            }
        }
        return false;
    }
}
