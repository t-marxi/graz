pragma solidity ^0.4.18;

library SafeMath {

    function mul(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal constant returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal constant returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }

}

contract ERC20Basic {
    uint256 public totalSupply;

    function balanceOf(address who) constant public returns (uint256);

    function transfer(address to, uint256 value) public returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract ERC20 is ERC20Basic {
    function allowance(address owner, address spender) constant public returns (uint256);

    function transferFrom(address from, address to, uint256 value) public returns (bool);

    function approve(address spender, uint256 value) public returns (bool);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Owned {

    address public owner;

    address public newOwner;

    function Owned() public payable {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    function changeOwner(address _owner) onlyOwner public {
        require(_owner != 0);
        newOwner = _owner;
    }

    function confirmOwner() public {
        require(newOwner == msg.sender);
        owner = newOwner;
        delete newOwner;
    }
}

contract Blocked {

    uint public blockedUntil;

    modifier unblocked {
        require(now > blockedUntil);
        _;
    }
}

contract BasicToken is ERC20Basic, Blocked {

    using SafeMath for uint256;

    mapping (address => uint256) balances;

    // Fix for the ERC20 short address attack
    modifier onlyPayloadSize(uint size) {
        require(msg.data.length >= size + 4);
        _;
    }

    function transfer(address _to, uint256 _value) onlyPayloadSize(2 * 32) unblocked public returns (bool) {
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        Transfer(msg.sender, _to, _value);
        return true;
    }

    function balanceOf(address _owner) constant public returns (uint256 balance) {
        return balances[_owner];
    }

}

contract StandardToken is ERC20, BasicToken {

    mapping (address => mapping (address => uint256)) allowed;

    function transferFrom(address _from, address _to, uint256 _value) onlyPayloadSize(3 * 32) unblocked public returns (bool) {
        var _allowance = allowed[_from][msg.sender];

        balances[_to] = balances[_to].add(_value);
        balances[_from] = balances[_from].sub(_value);
        allowed[_from][msg.sender] = _allowance.sub(_value);
        Transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) onlyPayloadSize(2 * 32) unblocked public returns (bool) {

        require((_value == 0) || (allowed[msg.sender][_spender] == 0));

        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) onlyPayloadSize(2 * 32) unblocked constant public returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

}

contract BurnableToken is StandardToken {

    event Burn(address indexed burner, uint256 value);

    function burn(uint256 _value) unblocked public {
        require(_value > 0);
        require(_value <= balances[msg.sender]);
        // no need to require value <= totalSupply, since that would imply the
        // sender's balance is greater than the totalSupply, which *should* be an assertion failure

        address burner = msg.sender;
        balances[burner] = balances[burner].sub(_value);
        totalSupply = totalSupply.sub(_value);
        Burn(burner, _value);
    }
}

contract DEVCoin is BurnableToken, Owned {

    string public constant name = "Dev Coin";

    string public constant symbol = "DEVC";

    uint32 public constant decimals = 18;

    function DEVCoin(uint256 initialSupply, uint unblockTime) public {
        totalSupply = initialSupply;
        balances[owner] = initialSupply;
        blockedUntil = unblockTime;
    }

    function manualTransfer(address _to, uint256 _value) onlyPayloadSize(2 * 32) onlyOwner public returns (bool) {
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        Transfer(msg.sender, _to, _value);
        return true;
    }
}

contract ManualSendingCrowdsale is Owned {
    using SafeMath for uint256;

    struct AmountData {
        bool exists;
        uint256 value;
    }

    mapping (uint => AmountData) public amountsByCurrency;

    function addCurrency(uint currency) external onlyOwner {
        addCurrencyInternal(currency);
    }

    function addCurrencyInternal(uint currency) internal {
        AmountData storage amountData = amountsByCurrency[currency];
        amountData.exists = true;
    }

    function manualTransferTokensToInternal(address to, uint256 givenTokens, uint currency, uint256 amount) internal returns (uint256) {
        AmountData memory tempAmountData = amountsByCurrency[currency];
        require(tempAmountData.exists);
        AmountData storage amountData = amountsByCurrency[currency];
        amountData.value = amountData.value.add(amount);
        return transferTokensTo(to, givenTokens);
    }

    function transferTokensTo(address to, uint256 givenTokens) internal returns (uint256);
}

contract Crowdsale is ManualSendingCrowdsale {

    using SafeMath for uint256;

    enum State { PRE_ICO, ICO }

    State public state = State.PRE_ICO;

    // Date of start pre-ICO and ICO.
    uint public constant preICOstartTime =    1514160000; // start at Monday, December 25, 2017 12:00:00 AM
    uint public constant preICOendTime =      1516752000; // end at   Wednesday, January 24, 2018 12:00:00 AM
    uint public constant ICOstartTime =    1516838400; // start at Thursday, January 25, 2018 12:00:00 AM
    uint public constant ICOendTime =      1519430400; // end at Saturday, February 24, 2018 12:00:00 AM

    uint public constant bountyAvailabilityTime = ICOendTime + 90 days;

    uint256 public constant maxTokenAmount = 35000000 * 10**18; // max minting
    uint256 public constant bountyTokens =    1750000 * 10**18; // bounty amount

    uint256 public constant maxPreICOTokenAmount = 5000000 * 10**18; // max number of tokens on pre-ICO;

    DEVCoin public token;

    uint256 public leftTokens = 0;

    uint256 public totalAmount = 0;
    uint public transactionCounter = 0;

    /** ------------------------------- */
    /** Bonus part: */

    // Amount bonuses
    uint private firstAmountBonus = 20;
    uint256 private firstAmountBonusBarrier = 50 ether;
    uint private secondAmountBonus = 10;
    uint256 private secondAmountBonusBarrier = 100 ether;

    // pre-ICO bonuses by time
    uint private preICOBonus = 15;
    uint private firstPreICOTimeBarrier = preICOstartTime + 1 days;
    uint private firstPreICOTimeBonus = 15;
    uint private secondPreICOTimeBarrier = preICOstartTime + 7 days;
    uint private secondPreICOTimeBonus = 10;

    // ICO bonuses by time
    uint private firstICOTimeBarrier = ICOstartTime + 1 days;
    uint private firstICOTimeBonus = 20;
    uint private secondICOTimeBarrier = ICOstartTime + 3 days;
    uint private secondICOTimeBonus = 15;
    uint private thirdICOTimeBarrier = ICOstartTime + 6 days;
    uint private thirdICOTimeBonus = 10;
    uint private fourthICOTimeBarrier = ICOstartTime + 14 days;
    uint private fourthICOTimeBonus = 5;

    /** ------------------------------- */

    bool public bonusesPayed = false;

    uint256 public constant rateToEther = 5000; // rate to ether, how much tokens gives to 1 ether

    uint256 public constant minAmountForDeal = 10**17;

    modifier canBuy() {
        require(!isFinished());
        require(isPreICO() || isICO());
        _;
    }

    modifier minPayment() {
        require(msg.value >= minAmountForDeal);
        _;
    }

    function Crowdsale() public {
        //require(currentTime() < preICOstartTime);
        token = new DEVCoin(maxTokenAmount, ICOendTime);
        leftTokens = maxPreICOTokenAmount;
        addCurrencyInternal(0); // add BTC
    }

    function isFinished() public constant returns (bool) {
        return currentTime() > ICOendTime || (leftTokens == 0 && state == State.ICO);
    }

    function isPreICO() public constant returns (bool) {
        var curTime = currentTime();
        return curTime < preICOendTime && curTime > preICOstartTime;
    }

    function isICO() public constant returns (bool) {
        var curTime = currentTime();
        return curTime < ICOendTime && curTime > ICOstartTime;
    }

    function() external canBuy minPayment payable {
        uint256 amount = msg.value;
        uint bonus = getBonus(amount);
        uint256 givenTokens = amount.mul(rateToEther).div(100).mul(100 + bonus);
        uint256 providedTokens = transferTokensTo(msg.sender, givenTokens);

        if (givenTokens > providedTokens) {
            uint256 needAmount = providedTokens.mul(100).div(100 + bonus).div(rateToEther);
            require(amount > needAmount);
            require(msg.sender.call.gas(3000000).value(amount - needAmount)());
            amount = needAmount;
        }
        totalAmount = totalAmount.add(amount);
    }

    function manualTransferTokensToWithBonus(address to, uint256 givenTokens, uint currency, uint256 amount) external canBuy onlyOwner returns (uint256) {
        uint bonus = getBonus(0);
        uint256 transferedTokens = givenTokens.mul(100 + bonus).div(100);
        return manualTransferTokensToInternal(to, transferedTokens, currency, amount);
    }

    function manualTransferTokensTo(address to, uint256 givenTokens, uint currency, uint256 amount) external onlyOwner canBuy returns (uint256) {
        return manualTransferTokensToInternal(to, givenTokens, currency, amount);
    }

    function getBonus(uint256 amount) public constant returns (uint) {
        uint bonus = 0;
        if (isPreICO()) {
            bonus = getPreICOBonus();
        }

        if (isICO()) {
            bonus = getICOBonus();
        }

        if (amount >= firstAmountBonusBarrier) {
            bonus = bonus + firstAmountBonus;
        }
        if (amount >= secondAmountBonusBarrier) {
            bonus = bonus + secondAmountBonus;
        }
        return bonus;
    }

    function getPreICOBonus() public constant returns (uint) {
        uint curTime = currentTime();
        if (curTime < firstPreICOTimeBarrier) {
            return firstPreICOTimeBonus + preICOBonus;
        }
        if (curTime < secondPreICOTimeBarrier) {
            return secondPreICOTimeBonus + preICOBonus;
        }
        return preICOBonus;
    }

    function getICOBonus() public constant returns (uint) {
        uint curTime = currentTime();
        if (curTime < firstICOTimeBarrier) {
            return firstICOTimeBonus;
        }
        if (curTime < secondICOTimeBarrier) {
            return secondICOTimeBonus;
        }
        if (curTime < thirdICOTimeBarrier) {
            return thirdICOTimeBonus;
        }
        if (curTime < fourthICOTimeBarrier) {
            return fourthICOTimeBonus;
        }
        return 0;
    }

    function finishCrowdsale() external {
        require(isFinished());
        require(state == State.ICO);
        if (leftTokens > 0) {
            token.burn(leftTokens);
            leftTokens = 0;
        }
    }

    function takeBounty() external onlyOwner {
        require(isFinished());
        require(state == State.ICO);
        require(now > bountyAvailabilityTime);
        require(!bonusesPayed);
        bonusesPayed = true;
        require(token.transfer(msg.sender, bountyTokens));
    }

    function startICO() external {
        require(currentTime() > preICOendTime);
        require(state == State.PRE_ICO && leftTokens <= maxPreICOTokenAmount);
        leftTokens = leftTokens.add(maxTokenAmount).sub(maxPreICOTokenAmount).sub(bountyTokens);
        state = State.ICO;
    }

    function transferTokensTo(address to, uint256 givenTokens) internal returns (uint256) {
        var providedTokens = givenTokens;
        if (givenTokens > leftTokens) {
            providedTokens = leftTokens;
        }
        leftTokens = leftTokens.sub(providedTokens);
        require(token.manualTransfer(to, providedTokens));
        transactionCounter = transactionCounter + 1;
        return providedTokens;
    }

    function withdraw() external onlyOwner {
        require(msg.sender.call.gas(3000000).value(this.balance)());
    }

    function withdrawAmount(uint256 amount) external onlyOwner {
        uint256 givenAmount = amount;
        if (this.balance < amount) {
            givenAmount = this.balance;
        }
        require(msg.sender.call.gas(3000000).value(givenAmount)());
    }

    function currentTime() internal constant returns (uint) {
        return now;
    }
}
