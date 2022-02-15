pragma ton-solidity >= 0.57.0;

interface IHasTokenRoot {
    function getTokenRoot() external view responsible returns (address);
}
