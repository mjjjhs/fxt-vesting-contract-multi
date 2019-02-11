pragma solidity ^0.4.23;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Claimable.sol';
import 'zeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import 'zeppelin-solidity/contracts/token/ERC20/MintableToken.sol';


/**
* @title LimitedTransferToken
* @dev LimitedTransferToken defines the generic interface and the implementation to limit token
* transferability for different events. It is intended to be used as a base class for other token
* contracts.
* LimitedTransferToken has been designed to allow for different limiting factors,
* this can be achieved by recursively calling super.transferableTokens() until the base class is
* hit. For example:
*     function transferableTokens(address holder, uint64 time) constant public returns (uint256) {
*       return min256(unlockedTokens, super.transferableTokens(holder, time));
*     }
* A working example is VestedToken.sol:
* https://github.com/OpenZeppelin/zeppelin-solidity/blob/master/contracts/token/VestedToken.sol
*/

contract LimitedTransferToken is ERC20 {

    /**
    * @dev Checks whether it can transfer or otherwise throws.
    */
    modifier canTransfer(address _sender, uint256 _value) {
        require(_value <= transferableTokens(_sender, uint64(now)));
        _;
    }

    /**
    * @dev Checks modifier and allows transfer if tokens are not locked.
    * @param _to The address that will receive the tokens.
    * @param _value The amount of tokens to be transferred.
    */
    function transfer(address _to, uint256 _value) canTransfer(msg.sender, _value) public returns (bool) {
        return super.transfer(_to, _value);
    }

    /**
    * @dev Checks modifier and allows transfer if tokens are not locked.
    * @param _from The address that will send the tokens.
    * @param _to The address that will receive the tokens.
    * @param _value The amount of tokens to be transferred.
    */
    function transferFrom(address _from, address _to, uint256 _value) canTransfer(_from, _value) public returns (bool) {
        return super.transferFrom(_from, _to, _value);
    }

    /**
    * @dev Default transferable tokens function returns all tokens for a holder (no limit).
    * @dev Overwriting transferableTokens(address holder, uint64 time) is the way to provide the
    * specific logic for limiting token transferability for a holder over time.
    */
    function transferableTokens(address holder, uint64 time) public view returns (uint256) {
        return balanceOf(holder);
    }
}


/*
Smart Token interface
*/
contract ISmartToken {

    // =================================================================================================================
    //                                      Members
    // =================================================================================================================

    bool public transfersEnabled = true;

    // =================================================================================================================
    //                                      Event
    // =================================================================================================================

    // triggered when a smart token is deployed - the _token address is defined for forward compatibility, in case we want to trigger the event from a factory
    event NewSmartToken(address _token);
    // triggered when the total supply is increased
    event Issuance(uint256 _amount);
    // triggered when the total supply is decreased
    event Destruction(uint256 _amount);

    // =================================================================================================================
    //                                      Functions
    // =================================================================================================================

    function disableTransfers(bool _disable) public;
    function issue(address _to, uint256 _amount) public;
    function destroy(address _from, uint256 _amount) public;
}


/**
BancorSmartToken
*/
contract LimitedTransferBancorSmartToken is MintableToken, ISmartToken, LimitedTransferToken {

    // =================================================================================================================
    //                                      Modifiers
    // =================================================================================================================

    /**
    * @dev Throws if destroy flag is not enabled.
    */
    modifier canDestroy() {
        require(destroyEnabled);
        _;
    }

    // =================================================================================================================
    //                                      Members
    // =================================================================================================================

    // We add this flag to avoid users and owner from destroy tokens during crowdsale,
    // This flag is set to false by default and blocks destroy function,
    // We enable destroy option on finalize, so destroy will be possible after the crowdsale.
    bool public destroyEnabled = false;

    // =================================================================================================================
    //                                      Public Functions
    // =================================================================================================================

    function setDestroyEnabled(bool _enable) onlyOwner public {
        destroyEnabled = _enable;
    }

    // =================================================================================================================
    //                                      Impl ISmartToken
    // =================================================================================================================

    //@Override
    function disableTransfers(bool _disable) onlyOwner public {
        transfersEnabled = !_disable;
    }

    //@Override
    function issue(address _to, uint256 _amount) public {
        require(super.mint(_to, _amount));
        emit Issuance(_amount);
    }

    //@Override
    function destroy(address _from, uint256 _amount) canDestroy public {

        require(msg.sender == _from || msg.sender == owner); // validate input

        balances[_from] = balances[_from].sub(_amount);
        totalSupply_ = totalSupply_.sub(_amount);

        emit Destruction(_amount);
        emit Transfer(_from, 0x0, _amount);
    }

    // =================================================================================================================
    //                                      Impl LimitedTransferToken
    // =================================================================================================================


    // Enable/Disable token transfer
    // Tokens will be locked in their wallets until the end of the Crowdsale.
    // @holder - token`s owner
    // @time - not used (framework unneeded functionality)
    //
    // @Override
    function transferableTokens(address holder, uint64 time) public constant returns (uint256) {
        require(transfersEnabled);
        return super.transferableTokens(holder, time);
    }
}




/**
A Token which is 'Bancor' compatible and can mint new tokens and pause token-transfer functionality
*/
contract FuzexSmartToken is LimitedTransferBancorSmartToken, Claimable {

    // =================================================================================================================
    //                                         Members
    // =================================================================================================================

    string public name = "FUZEX";

    string public symbol = "FXT";

    uint8 public decimals = 18;

    // =================================================================================================================
    //                                         Constructor
    // =================================================================================================================

    constructor() public {
        //Apart of 'Bancor' computability - triggered when a smart token is deployed
        emit NewSmartToken(address(this));
    }
}
