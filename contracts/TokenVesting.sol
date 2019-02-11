/* solium-disable security/no-block-members */
pragma solidity ^0.4.23;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/token/ERC20/ERC20Basic.sol';
import 'zeppelin-solidity/contracts/ownership/Claimable.sol';

/**
* @title TokenVesting
* @dev A token holder contract that can release its token balance gradually like a
* typical vesting scheme, with a cliff and vesting period. Optionally revocable by the
* owner.
*/
contract TokenVesting is Claimable {
    using SafeMath for uint256;

    event Released(uint256 amount);
    event Registered(address beneficiary, uint256 cliff, uint256 duration, uint256 periodUnit, uint256 amount);
    event Start(address beneficiary, uint256 start);
    event Revoked(address beneficiary, uint256 vestedAmount);

    uint256 totalAmount;
    uint256 totalReleased;

    struct VestingSchedule {
        uint256 cliff;
        uint256 start;
        uint256 duration;        // number of periods until done.
        uint256 amount;       // Total amount of tokens to be vested.
        uint256 released;   // The amount that has been withdrawn.
        uint256 periodUnit;
    }

    ERC20Basic tokenContract;

    // Schedule table for beneficiary
    mapping (address => VestingSchedule) public vestingTable;

    /**
    * @dev Creates a vesting contract that vests its balance of the ERC20 token.
    * @param _token address of the token contract to be vested
    */
    constructor(ERC20Basic _token) public {
        require(_token != address(0));
        tokenContract = _token;
        totalAmount = 0;
        totalReleased = 0;
    }

    function setBeneficiary(address _beneficiary, uint256 _cliff, uint256 _duration, uint256 _periodUnit, uint256 _amount) public onlyOwner {
        require(_beneficiary != address(0));
        require(vestingTable[_beneficiary].start == 0);
        require(_periodUnit != 0);
        if(vestingTable[_beneficiary].amount != 0){
            totalAmount = totalAmount.sub(vestingTable[_beneficiary].amount);
        }
        require(checkAmount(_amount));

        vestingTable[_beneficiary] = VestingSchedule({
            cliff : (_cliff * 1 minutes),
            start : 0,
            duration : (_duration * 1 minutes),
            amount : _amount,
            released : 0,
            periodUnit : (_periodUnit * 1 minutes)
        });
        totalAmount = totalAmount.add(_amount);
        emit Registered(_beneficiary, _cliff, _duration, _periodUnit, _amount);
    }

    function setMultipleBeneficiary(address[] _beneficiary, uint256[] _cliff, uint256[] _duration, uint256[] _periodUnit, uint256[] _amount) external onlyOwner {
        require(_beneficiary.length == _cliff.length);
        require(_beneficiary.length == _duration.length);
        require(_beneficiary.length == _periodUnit.length);
        require(_beneficiary.length == _amount.length);

        for(uint256 i = 0; i < _beneficiary.length; i++) {
            setBeneficiary(_beneficiary[i], _cliff[i], _duration[i], _periodUnit[i], _amount[i]);
        }
    }

    function setMultipleBeneficiaryWithSameParam(address[] _beneficiary, uint256 _cliff, uint256 _duration, uint256 _periodUnit, uint256 _amount) external onlyOwner {
        for(uint256 i = 0; i < _beneficiary.length; i++) {
            setBeneficiary(_beneficiary[i], _cliff, _duration, _periodUnit, _amount);
        }
    }

    function setStart(address _beneficiary) public onlyOwner{
        require(_beneficiary != address(0));
        require(vestingTable[_beneficiary].amount != 0);
        require(vestingTable[_beneficiary].start == 0);
        uint256 time = now;
        vestingTable[_beneficiary].start = time;
        emit Start(_beneficiary, time);
    }

    function setMultipleStart(address[] _beneficiary) external onlyOwner{
        for(uint256 i = 0; i < _beneficiary.length; i++){
            setStart(_beneficiary[i]);
        }
    }

    function checkAmount(uint256 _amount) public view onlyOwner returns (bool){
        uint256 reserveAmount = totalAmount.sub(totalReleased);
        if(tokenContract.balanceOf(this) >= reserveAmount.add(_amount)){
            return true;
        } else {
            return false;
        }
    }

    /**
    * @notice Transfers vested tokens to beneficiary.
    * @param _beneficiary beneficiary address
    */
    function release(address _beneficiary) public {
        require(_beneficiary == msg.sender || owner == msg.sender);
        uint256 unreleased = releasableAmount(_beneficiary);
        require(unreleased > 0);
        vestingTable[_beneficiary].released = vestingTable[_beneficiary].released.add(unreleased);
        totalReleased = totalReleased.add(unreleased);

        tokenContract.transfer(_beneficiary, unreleased);
        emit Released(unreleased);
        if(checkReleaseAll(_beneficiary)){
            vestingTable[_beneficiary].start = 0;
            vestingTable[_beneficiary].amount = 0;
        }
    }

    function multipleRelease(address[] _beneficiary) external onlyOwner {
        for(uint256 i = 0; i < _beneficiary.length; i++){
            if(releasableAmount(_beneficiary[i]) != 0){
                release(_beneficiary[i]);
            }
        }
    }

    function checkReleaseAll(address _beneficiary) internal view returns (bool){
        require(_beneficiary == msg.sender || owner == msg.sender);
        uint256 vestingAmount = vestingTable[_beneficiary].amount;
        uint256 releasedAmount = vestingTable[_beneficiary].released;
        if (vestingAmount == releasedAmount) {
            return true;
        } else {
            return false;
        }
    }

    /**
    * @notice Allows the owner or beneficiary to revoke the vesting. Tokens already vested
    * remain will send to beneficiary and the rest are returned to the owner.
    * @param _beneficiary beneficiary addess to revoke the vesting
    */
    function revoke(address _beneficiary) public {
        require(_beneficiary == msg.sender || owner == msg.sender);
        require(vestingTable[_beneficiary].start != 0);
        uint256 vested = vestedAmount(_beneficiary);
        uint256 remain = vestingTable[_beneficiary].amount.sub(vested);
        if(releasableAmount(_beneficiary) != 0){
            release(_beneficiary);
        }
        vestingTable[_beneficiary].start = 0;
        vestingTable[_beneficiary].amount = 0;
        totalAmount = totalAmount.sub(remain);
        emit Revoked(_beneficiary, vested);
    }


    /**
    * @dev Calculates the amount that has already vested but hasn't been released yet.
    * @param _beneficiary beneficiary address
    */
    function releasableAmount(address _beneficiary) public view returns (uint256) {
        require(_beneficiary == msg.sender || owner == msg.sender);
        if(vestingTable[_beneficiary].start != 0){
            uint256 released = vestingTable[_beneficiary].released;
            return vestedAmount(_beneficiary).sub(released);
        } else {
            return 0;
        }
    }

    /**
    * @dev Calculates the amount that has already vested.
    * @param _beneficiary beneficiary address
    */
    function vestedAmount(address _beneficiary) public view returns (uint256) {
        require(vestingTable[_beneficiary].start != 0);
        require(_beneficiary == msg.sender || owner == msg.sender);
        uint256 totalBalance = vestingTable[_beneficiary].amount;
        uint256 start = vestingTable[_beneficiary].start;
        uint256 cliff = start.add(vestingTable[_beneficiary].cliff);
        uint256 duration = vestingTable[_beneficiary].duration;
        uint256 periodUnit = vestingTable[_beneficiary].periodUnit;
        uint256 totalPeriods = duration / periodUnit;
        uint256 i = 0;


        if (block.timestamp < cliff) {
            return 0;
        } else if (block.timestamp >= start.add(duration)) {
            return totalBalance;
        } else {
            for(i = 1; i <= totalPeriods; i++){
               if(block.timestamp < start + (i * periodUnit)){
                    break;
                }
            }
            return (totalBalance/totalPeriods) * (i-1);
        }
    }

    function emergencyERC20Drain(ERC20Basic oddToken, uint amount) public onlyOwner{
        if (address(oddToken) == address(0)) {
            owner.transfer(amount);
            return;
        }
        oddToken.transfer(owner, amount);
    }
}
