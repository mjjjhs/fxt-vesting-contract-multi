import EVMRevert from "./helpers/EVMRevert";
import latestTime from "./helpers/latestTime";
import { increaseTimeTo, duration } from "./helpers/increaseTime";
const BigNumber = web3.BigNumber;
const eth = web3.eth;


require('chai')
.use(require('chai-as-promised'))
.use(require('chai-bignumber')(BigNumber))
.should();

const MintableToken = artifacts.require('FuzexSmartToken');
const TokenVesting = artifacts.require('TokenVesting');

contract('TokenVesting', function ([_, owner, beneficiary1, beneficiary2, beneficiary3, beneficiary4, beneficiary5, beneficiary6]) {
    const amount = new BigNumber(1000);
    const vestAmount = new BigNumber(200);

    beforeEach(async function () {
        this.token = await MintableToken.new({ from: owner });

        //this.start = latestTime() + duration.minutes(1); // +1 minute so it starts after contract instantiation
        this.cliff = 30;
        this.duration = 100;
        this.timeunit = 1;

        this.vesting = await TokenVesting.new(this.token.address, { from: owner });

        await this.token.mint(this.vesting.address, amount, { from: owner });
    });

    it('can be register vesting user', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
    });

    it('cannot be register vesting user', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.setBeneficiary(beneficiary2, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.setBeneficiary(beneficiary3, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.setBeneficiary(beneficiary4, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.setBeneficiary(beneficiary5, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.setBeneficiary(beneficiary6, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.rejectedWith(EVMRevert);
    });

    it('cannot be released before start', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(latestTime() + duration.minutes(100));
        await this.vesting.release(beneficiary1, { from: owner }).should.be.rejectedWith(EVMRevert);
    });

    it('can be start registered vesting user', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(latestTime() + duration.minutes(1));
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
    });

    it('cannot be released before cliff', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(latestTime() + duration.minutes(1));
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(latestTime() + duration.minutes(this.cliff - 1));
        await this.vesting.release(beneficiary1, { from: beneficiary1 }).should.be.rejectedWith(EVMRevert);
    });

    it('can be released after cliff', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(latestTime() + duration.minutes(1));
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(latestTime() + duration.minutes(this.cliff) + 1);
        await this.vesting.release(beneficiary1, { from: owner }).should.be.fulfilled;
    });

    it('should release proper amount after cliff', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        const start = latestTime() + 1;
        await increaseTimeTo(start);

        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(latestTime() + duration.minutes(this.cliff) + 1);

        const { receipt } = await this.vesting.release(beneficiary1, { from: beneficiary1 }).should.be.fulfilled;
        const releaseTime = web3.eth.getBlock(receipt.blockNumber).timestamp;

        const balance = await this.token.balanceOf(beneficiary1);
        balance.should.bignumber.equal(vestAmount.mul(releaseTime - start).div(duration.minutes(this.duration)).floor());
    });

    it('should linearly release tokens during vesting period', async function () {
        const vestingPeriod = this.duration - this.cliff;
        const checkpoints = 5;
        const start = latestTime() + 1;

        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(start);

        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;


        for (let i = 1; i <= checkpoints; i++) {
            const now = start + duration.minutes(this.cliff + i * (vestingPeriod / checkpoints));
            await increaseTimeTo(now + 1);

            await this.vesting.release(beneficiary1, { from: beneficiary1 });
            const balance = await this.token.balanceOf(beneficiary1);
            const expectedVesting = vestAmount.mul(now - start).div(duration.minutes(this.duration)).floor();
            balance.should.bignumber.equal(expectedVesting);
        }
    });

    it('should linearly release tokens (w/o cliff case)', async function () {
        const vestingPeriod = this.duration;
        const checkpoints = this.duration / 10;
        const start = latestTime() + 1;

        await this.vesting.setBeneficiary(beneficiary1, 0, this.duration, 10, vestAmount, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(start);

        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;


        for (let i = 1; i <= checkpoints; i++) {
            const now = start + duration.minutes(i * (checkpoints));
            await increaseTimeTo(now + 1);

            await this.vesting.release(beneficiary1, { from: beneficiary1 });
            const balance = await this.token.balanceOf(beneficiary1);
            const expectedVesting = vestAmount.mul(now - start).div(duration.minutes(this.duration)).floor();
            balance.should.bignumber.equal(expectedVesting);
        }
    });

    it('should have released all after end', async function () {
        const start = latestTime() + 1;

        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(start);

        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;

        await increaseTimeTo(start + duration.minutes(this.duration) + 1);
        await this.vesting.release(beneficiary1, { from: beneficiary1 });
        const balance = await this.token.balanceOf(beneficiary1);
        balance.should.bignumber.equal(vestAmount);
    });

    it('should be revoked by owner', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await this.vesting.revoke(beneficiary1, { from: owner }).should.be.fulfilled;
    });

    it('should be revoked by beneficiary', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await this.vesting.revoke(beneficiary1, { from: beneficiary1 }).should.be.fulfilled;
    });

    it('should fail to be revoked if the vesting has not been started', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        await this.vesting.revoke(beneficiary1, { from: owner }).should.be.rejectedWith(EVMRevert);
    });

    it('should return the non-vested tokens when revoked after then invoke emergencyERC20Drain function', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        const start = latestTime() + 1;
        await increaseTimeTo(start);
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(start + duration.minutes(this.cliff + 20) + 1);
        const vested = await this.vesting.vestedAmount(beneficiary1, {from: owner});
        await this.vesting.revoke(beneficiary1, { from: owner });
        await this.vesting.emergencyERC20Drain(this.token.address, vestAmount.sub(vested), { from: owner });
        const ownerBalance = await this.token.balanceOf(owner);
        ownerBalance.should.bignumber.equal(vestAmount.sub(vested));
    });

    it('should send current vested tokens to beneficiary when revoked', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        const start = latestTime() + 1;
        await increaseTimeTo(start);
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(start + duration.minutes(this.cliff + 20) + 1);
        const vested = await this.vesting.vestedAmount(beneficiary1, {from: owner});
        await this.vesting.revoke(beneficiary1, { from: owner });
        const balance = await this.token.balanceOf(beneficiary1);
        balance.should.bignumber.equal(vested);
    });

    it('should fail to be revoked a second time', async function () {
        await this.vesting.setBeneficiary(beneficiary1, this.cliff, this.duration, this.timeunit, vestAmount, { from: owner }).should.be.fulfilled;
        const start = latestTime() + 1;
        await increaseTimeTo(start);
        await this.vesting.setStart(beneficiary1, { from: owner }).should.be.fulfilled;
        await increaseTimeTo(start + duration.minutes(this.cliff + 20) + 1);
        const vested = await this.vesting.vestedAmount(beneficiary1, {from: owner});
        await this.vesting.revoke(beneficiary1, { from: owner });
        await this.vesting.revoke(beneficiary1, { from: owner }).should.be.rejectedWith(EVMRevert);
    });

});
