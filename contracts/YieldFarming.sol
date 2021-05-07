// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.6;


import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.0.0/contracts/token/ERC20/IERC20.sol';
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.0.0/contracts/token/ERC20/SafeERC20.sol';
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.0.0/contracts/math/SafeMath.sol';
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.0.0/contracts/access/Ownable.sol";
import './MockToken.sol';


contract SimpleYieldContract is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    MockToken public mockToken;

    uint256 public bonusEachBlock;
    uint256 public mockTokenPerBlock;
    uint256 public totalAllocPoint = 0;

    uint256 public constant BONUS_MULTIPLIER = 2;


    // staker information
    struct StakerInfo {
        uint256 amount;
        uint256 rewardWaiting;
    }
    // pool information
    struct PoolInfo {
        IERC20 poolToken;
        uint256 lastRewardBlock;
        uint256 allocPoint;
        uint256 accMockPerShare;
    }

    PoolInfo[] public poolInfo;

    mapping(uint256 => mapping(address => StakerInfo)) public stakerInfo;


    uint256 public startBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        MockToken _mockToken,
        uint256 _bonusEachBlock,
        uint256 _mockTokenPerBlock,
        uint256 _startBlock
        
    ) public {
        mockToken = _mockToken;
        bonusEachBlock = _bonusEachBlock;
        mockTokenPerBlock = _mockTokenPerBlock;
        startBlock = _startBlock;
    }

    // define the logic for rewarding each new block
    function rewardBlockLogic(uint256 _from, uint256 _to) public view returns(uint256){
         if (_to <= bonusEachBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEachBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEachBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEachBlock)
                );
        }
    }


    // create a new pool only owner is authorized
    function newPool(
        IERC20 _poolToken,
        uint256 _allocPoint
    ) public onlyOwner {
        uint256 latestRewardBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo.push(
            PoolInfo({
                poolToken: _poolToken,
                lastRewardBlock: latestRewardBlock,
                allocPoint: _allocPoint,
                accMockPerShare: 0
            })
        );
    }

    // calculate the pending reward
    function pendingReward(uint256 _pid, address _user) external view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        StakerInfo storage user = stakerInfo[_pid][_user];
        uint256 accMockPerShare = pool.accMockPerShare;
        uint256 poolTokenSupply = pool.poolToken.balanceOf(address(this));
        if(block.number > pool.lastRewardBlock && poolTokenSupply != 0) {
            uint256 multiplier = rewardBlockLogic(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(mockTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accMockPerShare = accMockPerShare.add(
                tokenReward.mul(1e12).div(poolTokenSupply));
            
            
        }
        return user.amount.mul(accMockPerShare).div(1e12).sub(user.rewardWaiting);
    }

    // Stake your erc20 token on the selected pool
    function stakeInPool(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        StakerInfo storage user = stakerInfo[_pid][msg.sender];
        if(user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accMockPerShare).div(1e12).sub(user.rewardWaiting);
            mockTokenTransfer(msg.sender, pending);
        }
        pool.poolToken.safeTransferFrom(
            address(msg.sender), address(this), _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardWaiting = user.amount.mul(pool.accMockPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // get all the information of a pool
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return (pool.poolToken, pool.latestRewardBlock, pool.allocPoint, pool.accMockPerShare);
    }


    // get all information of a staker inside a pool
    function stakerInfo(uint256 _pid, address _user) external view returns (uint256, uint256) {
        StakerInfo storage user = stakerInfo[_pid][_user];
        return (user.amount, user.rewardWaiting);
    }


    // withdraw your erc20 token from the pool
    function withdrawFromPool(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        StakerInfo storage user = stakerInfo[_pid][msg.sender];
        require(user.amount >= _amount, "you can't withdraw what you don't have");
        uint256 pending = user.amount.mul(pool.accMockPerShare).div(1e12).sub(user.rewardWaiting);
        mockTokenTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardWaiting = user.amount.mul(pool.accMockPerShare).div(1e12);
        pool.poolToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }



    // logic to transfer the mock token
    function mockTokenTransfer(address _to, uint256 _amount) internal {
        uint256 mockBalance = mockToken.balanceOf(address(this));
        if(_amount > mockBalance) {
            mockToken.transfer(_to, mockBalance);
        } else {
            mockToken.transfer(_to, _amount);
        }
    }



}

