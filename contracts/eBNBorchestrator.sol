
/*created by:Prabhakaran(@Prabhakaran1998)
             Martina(@Martinagracy28)    
Role:solidity Developer-boson labs
date:28-Nov-2020
reviewed by:hemadri -project director-Boson Labs */
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.24;
import "./eBNBpolicy.sol";

/**
 * @title eBNB Orchestrator
 * @notice The eBNBorchestrator is the main entry point for rebase operations. It coordinates the eBNBpolicyref
 * actions with external consumers.
 */
contract eBNBOrchestrator is OwnableUpgradeSafe {
struct Transaction {
        bool enabled;
        address destination;
        bytes data;
    }

    event TransactionFailed(address indexed destination, uint index, bytes data);
    Transaction[] public transactions;
    eBNBPolicy public eBNBpolicyref;

    /**
       Here we Initializing address of
     * @param eBNBpolicyref_ Address of the  eBNBpolicy.
     */
     function initialize(address eBNBpolicyref_) public {
        OwnableUpgradeSafe.__Ownable_init();
        eBNBpolicyref = eBNBPolicy(eBNBpolicyref_);
    }

    /**
     * @notice Main entry point to initiate a rebase operation.
     *         The eBNBOrchestrator calls rebase on the eBNBpolicyref and notifies downstream applications.
     *         Contracts are guarded from calling, to avoid flash loan attacks on liquidity
     *         providers.
     *         If a transaction in the transaction list reverts, it is swallowed and the remaining
     *         transactions are executed.
     */
    function rebase()
        external
         onlycoowner
    {
        require(msg.sender == tx.origin); 
        eBNBpolicyref.rebase();

        for (uint i = 0; i < transactions.length; i++) {
            Transaction storage t = transactions[i];
            if (t.enabled) {
                bool result =
                    externalCall(t.destination, t.data);
                   
                if (!result) {
                    emit TransactionFailed(t.destination, i, t.data);
                    revert("Transaction Failed");
                }
            }
        }
    }

    /**
     * @notice Adds a transaction that gets called for a downstream receiver of rebases
     * @param destination Address of contract destination
     * @param data Transaction data payload
     */
    function addTransaction(address  destination, bytes calldata data)
        external
        onlyOwner
    {
        transactions.push(Transaction({
            enabled: true,
            destination: destination,
            data: data
        }));
    }

    /**
     * @param index Index of transaction to remove.
     *              Transaction ordering may have changed since adding.
     */
    function removeTransaction(uint index)
        external
        onlyOwner
    {
        require(index < transactions.length, "index out of bounds");

        if (index < transactions.length - 1) {
            transactions[index] = transactions[transactions.length - 1];
        }

        transactions[transactions.length - 1];
    }

    /**
     * @param index Index of transaction. Transaction ordering may have changed since adding.
     * @param enabled True for enabled, false for disabled.
     */
    function setTransactionEnabled(uint index, bool enabled)
        external
        onlyOwner
    {
        require(index < transactions.length, "index must be in range of stored tx list");
        transactions[index].enabled = enabled;
    }

    /**
     * @return Number of transactions, both enabled and disabled, in transactions list.
     */
    function transactionsSize()
        external
        view
        returns (uint256)
    {
        return transactions.length;
    }

    /**
     * @dev wrapper to call the encoded transactions on downstream consumers.
     * @param destination Address of destination contract.
     * @param data The encoded data payload.
     * @return True on success
     */
    function externalCall(address  destination, bytes memory data)
        internal
        returns (bool)
    {
        bool result;
        assembly {  
            // "Allocate" memory for output
            // (0x40 is where "free memory" pointer is stored by convention)
            let outputAddress := mload(0x40)

            // First 32 bytes are the padded length of data, so exclude that
            let dataAddress := add(data, 32)

            result := call(
                // 34710 is the value that solidity is currently emitting
                // It includes callGas (700) + callVeryLow (3, to pay for SUB)
                // + callValueTransferGas (9000) + callNewAccountGas
                // (25000, in case the destination address does not exist and needs creating)
                sub(gas() ,34710),
                destination,
                0, // transfer value in wei
                dataAddress,
                mload(data),  // Size of the input, in bytes. Stored in position 0 of the array.
                outputAddress,
                0  // Output is ignored, therefore the output size is zero
            )
        }
        return result;
    }
}