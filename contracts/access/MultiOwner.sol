pragma ton-solidity >= 0.57.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "@broxus/contracts/contracts/_ErrorCodes.sol";

abstract contract MultiOwner {
    address public admin;
    uint[] public owners;

    event OwnerAdded(uint newOwner);

    modifier anyOwner() {
        require(isOwner(), _ErrorCodes.NOT_OWNER);
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, _ErrorCodes.NOT_OWNER);
        _;
    }

    function addOwner(uint newOwner) external anyOwner {
        require(newOwner != 0, _ErrorCodes.ZERO_OWNER);
        tvm.accept();

        owners.push(newOwner);
        emit OwnerAdded(newOwner);
    }

    function resetOwners() external onlyAdmin {
        tvm.accept();

        owners = new uint256[](0);
    }

    function isOwner() private returns(bool) {
        for (uint i = 0; i < owners.length; i++) {
            if(owners[i] == msg.pubkey())
            {
                return true;
            }
        }
        if (msg.sender == admin) {
            return true;
        }
        for (uint i = 0; i < owners.length; i++) {
            if(owners[i] == msg.sender.value && msg.sender.wid == address(this).wid)
            {
                return true;
            }
        }
        return false;
    }
}
