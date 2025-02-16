// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../core/Helpers.sol";
import "../core/BaseAccount.sol";

/**
 * Simple7702Account.sol
 * A minimal account to be used with EIP-7702 (for batching) and ERC-4337 (for gas sponsoring)
 */
contract Simple7702Account is BaseAccount, IERC165, IERC1271, ERC1155Holder, ERC721Holder {

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    // temporary address of entryPoint v0.8
    function entryPoint() public pure override returns (IEntryPoint) {
        return IEntryPoint(0x9dab3AEd4B71E1AF22550b28ebae79c955F7041e);
    }

    /**
     * Make this account callable through ERC-4337 EntryPoint.
     * The UserOperation should be signed by this account's private key.
     */
    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256 validationData) {

        return _checkSignature(userOpHash, userOp.signature) ? 0 : SIG_VALIDATION_FAILED;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) public view returns (bytes4 magicValue) {
        return _checkSignature(hash, signature) ? this.isValidSignature.selector : bytes4(0);
    }

    function _checkSignature(bytes32 hash, bytes memory signature) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == address(this);
    }

    function _requireFromSelfOrEntryPoint() internal view virtual {
        require(
            msg.sender == address(this) ||
            msg.sender == address(entryPoint()),
            "not from self or EntryPoint"
        );
    }


    function execute(Call[] calldata calls) external {
        _requireFromSelfOrEntryPoint();

        for (uint256 i = 0; i < calls.length; i++) {
            Call calldata call = calls[i];
            (bool ok, bytes memory ret) = call.target.call{value: call.value}(call.data);
            if (!ok) {
                // solhint-disable-next-line no-inline-assembly
                assembly {revert(add(ret, 32), mload(ret))}
            }
        }
    }

    function supportsInterface(bytes4 id) public override(ERC1155Holder, IERC165) pure returns (bool) {
        return
            id == type(IERC165).interfaceId ||
            id == type(IAccount).interfaceId ||
            id == type(IERC1271).interfaceId ||
            id == type(IERC1155Receiver).interfaceId ||
            id == type(IERC721Receiver).interfaceId;
    }

    // accept incoming calls (with or without value), to mimic an EOA.
    fallback() external payable {
    }

    receive() external payable {
    }
}
