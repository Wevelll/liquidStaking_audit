//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "../libs/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../libs/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/DappsStaking.sol";
import "./nDistributor.sol";

//shibuya: 0xD9E81aDADAd5f0a0B59b1a70e0b0118B85E2E2d3
contract LiquidStaking is Initializable, AccessControlUpgradeable {
    DappsStaking public constant DAPPS_STAKING = DappsStaking(0x0000000000000000000000000000000000005001);
    bytes32 public constant            MANAGER = keccak256("MANAGER");

    string public utilName; // LiquidStaking
    string public DNTname; // nASTR

    uint256 public totalBalance;
    uint256 public minStake;
    uint256 public withdrawBlock;

    uint256 public unstakingPool;
    uint256 public rewardPool;

    address public distrAddr;
    NDistributor   distr;

    mapping(address => mapping(uint256 => bool)) public userClaimed;

    struct Stake {
        uint256 totalBalance;
        uint256 eraStarted;
    }
    mapping(address => Stake) public stakes;

    struct Withdrawal {
        uint256 val;
        uint256 eraReq;
    }
    mapping(address => Withdrawal[]) public withdrawals;

    struct eraData {
        bool done;
        uint256 val;
    }
    mapping(uint256 => eraData) public eraStaked; // total tokens staked per era
    mapping(uint256 => eraData) public eraUnstaked; // total tokens unstaked per era
    mapping(uint256 => eraData) public eraStakerReward; // total staker rewards per era
    mapping(uint256 => eraData) public eraDappReward; // total dapp rewards per era
    mapping(uint256 => eraData) public eraRevenue; // total revenue per era

    uint256 public unbondedPool;

    address public proxyAddr;

    uint256 public lastUpdated; // last era updated everything

    // Reward handlers
    mapping (address => uint) public rewardsByAddress;
    address[] public stakers;
    address public dntToken;
    mapping (address => bool) public isStaker;

    uint256 public lastStaked;
    uint256 public lastUnstaked;

    mapping (address => uint) private shadowTokensAmount;


    // ------------------ INIT
    // -----------------------
    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
        proxyAddr = msg.sender;
        lastUpdated = DAPPS_STAKING.read_current_era() - 1;
        lastStaked = 1175;
        lastUnstaked = 1178;
    }

    function setup() external onlyRole(MANAGER) {
        withdrawBlock = DAPPS_STAKING.read_unbonding_period();
        DNTname = "nSBY";
        utilName = "LiquidStaking";
    }


    // ------------------ ADMIN
    // ------------------------
    function set_distr(address _newDistr) public onlyRole(MANAGER) {
        distrAddr = _newDistr;
        distr = NDistributor(distrAddr);
    }

    function set_proxy(address _p) public onlyRole(MANAGER) {
        proxyAddr = _p;
    }

    function set_last(uint256 _val) public onlyRole(MANAGER) {
        lastUpdated = _val;
    }

    function set_lastS(uint256 _val) public onlyRole(MANAGER) {
        lastStaked = _val;
    }

    function set_lastU(uint256 _val) public onlyRole(MANAGER) {
        lastUnstaked = _val;
    }

    function set_dntToken(address _address) public onlyRole(MANAGER) {
        dntToken = _address;
    }


    // ------------------ VIEWS
    // ------------------------
    function current_era() public view returns(uint256) {
        return DAPPS_STAKING.read_current_era();
    }

    function get_stakers() public view returns(address[] memory) {
        require(msg.sender == dntToken && msg.sender != address(0), "> Only available for token contract!");
        return stakers;
    }

    // @notice returns user active withdrawals
    function get_user_withdrawals() public view returns(Withdrawal[] memory) {
        return withdrawals[msg.sender];
    }


    // ------------------ DAPPS_STAKING
    // --------------------------------
    function global_stake(uint128 val) public {
        //uint128 sum2stake = 0;
        //uint128 val = uint128(eraStaked[_era].val);

        if (val > 0) {
            DAPPS_STAKING.bond_and_stake(proxyAddr, val);
            //eraStaked[_era].done = true;
        }
        /*
        for (uint256 i = lastStaked + 1; i <= _era;) {
            //sum2stake += uint128(eraStaked[i].val);
            unchecked { ++i; }
        }
        */

/*
        if(sum2stake != 0){
            DAPPS_STAKING.bond_and_stake(proxyAddr, sum2stake);
            lastStaked = _era;
        }
        */
    }

    function viewmuchstake(uint256 _era) public view returns(uint128) {
        uint128 sum2stake = 0;
        for (uint256 i = lastUnstaked + 1; i <= _era;) {
            sum2stake += uint128(eraStaked[i].val);

            unchecked { ++i; }
        }
        return sum2stake;
    }

    function global_unstake(uint256 _era) public {
        //uint128 sum2unstake = 0;

        DAPPS_STAKING.unbond_and_unstake(proxyAddr, uint128(eraUnstaked[_era].val));
        eraUnstaked[_era].done = true;
/*
        for (uint256 i = lastUnstaked + 1; i <= _era;) {
            eraUnstaked[i].done = true;
            sum2unstake += uint128(eraUnstaked[i].val);
            unchecked { ++i; }
        }
        if(sum2unstake != 0) {
            lastUnstaked = _era;
        }
*/
    }

    function global_withdraw(uint256 _era) public {
        for (uint i = lastUpdated + 1; i <= _era;) {

            if(eraUnstaked[i - withdrawBlock].val != 0) {

                uint256 p = address(proxyAddr).balance;
                DAPPS_STAKING.withdraw_unbonded();
                uint256 a = address(proxyAddr).balance;
                unbondedPool += a - p;

                break;
            }
            unchecked { ++i; }
        }
    }

    function global_claim(uint256 _era) public {
        // claim rewards
        uint256 p = address(proxyAddr).balance;
        DAPPS_STAKING.claim_staker(proxyAddr);
        uint256 a = address(proxyAddr).balance;

        uint256 coms = (a - p) / 100; // 1% comission to revenue pool

        eraStakerReward[_era].val = a - p - coms; // rewards to share between users
        eraRevenue[_era].val += coms;

        uint length = stakers.length;
        // iter on each staker and give him some rewards
        for (uint i; i < length;) {
            address stakerAddr = stakers[i];
            uint stakerDntBalance = distr.getUserDntBalanceInUtil(stakerAddr, utilName, DNTname);
            rewardsByAddress[stakerAddr] += eraStakerReward[_era].val * (stakerDntBalance + shadowTokensAmount[stakerAddr]) / totalBalance;
            unchecked { ++i; }
        }
    }



    // ------------------ MISC
    // -----------------------
    function addStaker(address _addr) public {
        require(msg.sender == dntToken, "> Only available for token contract!");
        uint stakerDntBalance = distr.getUserDntBalanceInUtil(_addr, utilName, DNTname);
        stakes[msg.sender].totalBalance = stakerDntBalance;
        rewardsByAddress[_addr] = 0;
        stakers.push(_addr);
    }

    function mintShadowTokens(address _user, uint _amount) public {
        require(msg.sender == distrAddr, "Not available");
        shadowTokensAmount[_user] += _amount;
    }

    function burnShadowTokens(address _user, uint _amount) public {
        require(msg.sender == distrAddr, "Not available");
        shadowTokensAmount[_user] -= _amount;
    }

    function fill_pools(uint256 _era) public {

        for (uint i = lastUpdated + 1; i <= _era;) {
            eraRevenue[i].done = true;
            unstakingPool += eraRevenue[i].val / 10; // 10% of revenue goes to unstaking pool
            unchecked { ++i; }
        }

        eraStakerReward[_era].done = true;
        rewardPool += eraStakerReward[_era].val;
    }

    function fill_unbonded() external payable {
        require(msg.value > 0, "Provide some value!");
        unbondedPool += msg.value;
    }

    function fill_unstaking() external payable {
        require(msg.value > 0, "Provide some value!");
        unstakingPool += msg.value;
    }


    // -------------- USER FUNCS
    // -------------------------
    function stake() external payable updateAll {
        Stake storage s = stakes[msg.sender];
        uint256 era = current_era();
        uint256 val = msg.value;

        totalBalance += val;
        eraStaked[era].val += val;

        s.totalBalance += val;
        s.eraStarted = s.eraStarted == 0 ? era : s.eraStarted;

        if (!isStaker[msg.sender]) {
            isStaker[msg.sender] = true;
            stakers.push(msg.sender);
        }

        distr.issueDnt(msg.sender, val, utilName, DNTname);
    }

    function unstake(uint256 _amount, bool _immediate) external updateAll {
        uint userDntBalance = distr.getUserDntBalanceInUtil(msg.sender, utilName, DNTname);
        Stake storage s = stakes[msg.sender];

        // check if user have enough nTokens
        require(userDntBalance >= _amount, "> Not enough nASTR!");
        require(_amount > 0, "Invalid amount!");

        uint256 era = current_era();
        eraUnstaked[era].val += _amount;

        totalBalance -= _amount;
        // check current stake balance of user
        // set it zero if not enough
        // reduce else
        if (s.totalBalance >= _amount) {
            s.totalBalance -= _amount;
        } else {
            s.totalBalance = 0;
            s.eraStarted = 0;
        }
        distr.removeDnt(msg.sender, _amount, utilName, DNTname);

        if (_immediate) {
            require(unstakingPool >= _amount, "Unstaking pool drained!");
            uint256 fee = _amount / 100; // 1% immediate unstaking fee
            eraRevenue[era].val += fee;
            unstakingPool -= _amount;
            payable(msg.sender).transfer(_amount - fee);
        } else {
            withdrawals[msg.sender].push(Withdrawal({
                val: _amount,
                eraReq: era
            }));
        }
    }

    function claim(uint _amount) external updateAll {
        require(rewardPool >= _amount, "Rewards pool drained!");
        require(rewardsByAddress[msg.sender] >= _amount, "> Not enough rewards!");
        rewardPool -= _amount;
        rewardsByAddress[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
    }

    function withdraw(uint256 _id) external updateAll {
        Withdrawal storage w = withdrawals[msg.sender][_id];
        uint256 val = w.val;
        uint256 era = current_era();

        require(era - w.eraReq >= withdrawBlock, "Not enough eras passed!");
        require(unbondedPool >= val, "Unbonded pool drained!");

        unbondedPool -= val;
        w.eraReq = 0;

        payable(msg.sender).transfer(val);
    }

    modifier updateAll { // each user call triggers global update
        uint256 era = current_era() - 1; // last era to update
        if (lastUpdated != era) {
            global_withdraw(era);
            global_claim(era);
            //global_stake(era);
            //global_unstake(era);
            fill_pools(era);
            lastUpdated = era;
        }
        _;
    }
    function claim_dapp(uint256 _era) public {
        /*
        require(current_era() != _era, "Cannot claim yet!");
        require(eraDappReward[_era].val == 0, "Already claimed!");
        uint256 p = address(proxyAddr).balance;
        */
        DAPPS_STAKING.claim_dapp(proxyAddr, uint128(_era));
        /*
        uint256 a = address(proxyAddr).balance;
        uint256 coms = (a - p) / 10; // 10% goes to revenue pool
        eraDappReward[_era].val = a - p - coms;
        eraRevenue[_era].val += coms;
        */
    }
    // function claim(uint256 _era) external updateAll {
    //     require(!userClaimed[msg.sender][_era], "Already claimed!");
    //     userClaimed[msg.sender][_era] = true;
    //     uint256 reward = user_reward(_era);
    //     require(rewardPool >= reward, "Rewards pool drained!");
    //     rewardPool -= reward;
    //     payable(msg.sender).transfer(reward);
    // }

}
