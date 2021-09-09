//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import {Utils88mph} from "./utils/Utils88mph.sol";
import {AirswapUtils} from "./utils/AirswapUtils.sol";
import {RollOverBase} from "./utils/RollOverBase.sol";
import {GammaUtils} from "./utils/GammaUtils.sol";
import {ZeroXUtils} from "./utils/ZeroXUtils.sol";
import {SwapTypes} from "./libraries/SwapTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IController} from "./interfaces/IController.sol";
import {IAction} from "./interfaces/IAction.sol";
import {IOToken} from "./interfaces/IOToken.sol";

import "hardhat/console.sol";

contract StructuredProduct is IAction, Utils88mph, AirswapUtils, RollOverBase, GammaUtils {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bool vaultClosed;

    /// @dev 100%
    uint256 public constant BASE = 10000;

    /// @dev amount of assets locked in Opyn and 88mph
    uint256 public lockedAsset;

    /// @dev time at which the last rollover was called
    uint256 public rolloverTime;

    uint256 public minPeriod;

    /// @dev address of the vault 
    address public immutable vault;

    /// @dev address of the ERC20 asset. Do not use non-ERC20s
    address public immutable asset;

    address public immutable usdc; 

    Position position = Position.Meh;

    enum Position{Meh, Long, Short}




    /** 
    * @notice constructor 
    * @param _vault the address of the vault contract
    * @param _asset address of the ERC20 asset
    * @param _mph_vesting mph vesting contract address
    * @param uniRouter uniswapv2 router 
    * @param  _mph_token mph erc20 token address
    * @param _airswap address of airswap swap contract 
    * @param _controller address of Opyn controller contract
    */
    constructor(
      address _vault,
      address _asset, // weth
      address _airswap,
      address _controller,
      address _firb,
      address _mph_vesting,
      address _mph_token,
      address uniRouter,
      address _usdc,
      uint256 _vaultType
    ) {
      vault = _vault;
      asset = _asset;

      // enable vault to take all the asset back and re-distribute.
      IERC20(_asset).safeApprove(_vault, uint256(-1));

      _initGammaUtil(_controller);

      // enable pool contract to pull asset from this contract to mint options.
      address pool = controller.pool();

      address whitelist = controller.whitelist();

      usdc = _usdc;

      _initSwapContract(_airswap);

      // assuming asset is weth
      _init88mphUtils(_firb, _mph_vesting, _mph_token, uniRouter);

      _initRollOverBase(whitelist);
      __Ownable_init();
      
      _openGammaVault(_vaultType);
    }

    modifier onlyVault() {
      require(msg.sender == vault, "!VAULT");

      _;
    }

    /**
    * @notice returns the net worth of this strategy = current balance of the action + collateral deposited into Opyn's vault. 
    * @dev For a more realtime tracking of value, we reccomend calculating the current value as: 
    * currentValue = balance + collateral - (numOptions * cashVal), where: 
    * balance = current balance in the action
    * collateral = collateral deposited into Opyn's vault 
    * numOptions = number of options sold
    * cashVal = cash value of 1 option sold (for puts: Strike - Current Underlying Price, for calls: Current Underlying Price - Strike)
    */
    function currentValue() external view override returns (uint256) {
      uint256 assetBalance = IERC20(asset).balanceOf(address(this));
      return assetBalance.add(lockedAsset);
      // TODO:
    }

    /**
    * @notice the function that the vault will call when the new round is starting. Once this is called, the funds will be sent from the vault to this action. 
    * @dev this does NOT automatically mint FIRB. This merely receives funds. Before this function is called, the owner should have called 
    * `commitOToken` to decide on what Otoken is being sold. This function can only be called after the commitment period has passed since the call to `commitOToken`.
    * Once this has been called, the owner should call `mintFirb` and choose their position. If the owner doesn't mint a FIRB within 1 day after rollover has been 
    * called, someone can call closePosition and transfer the funds back to the vault. If that happens, the owner needs to commit to a new otoken and call rollover again. 
    */
    function rolloverPosition() external override onlyVault {
      _rollOverNextOTokenAndActivate(); // this function can only be called when the action is `Committed`
      rolloverTime = block.timestamp;
    }

    /**
    * @notice the function will return when someone can close a position. 1 day after rollover,
    * if the FIRB has not being minted, anyone can close the position and send funds back to the vault. 
    */
    function canClosePosition() public view returns (bool) {
      require(_firb_redeemable(), "firb isn't mature yet");
      if (otoken[0] != address(0) && lockedAsset != 0) {
        if(position == Position.Long)
          return _canSettleVault();
        if(position == Position.Short) 
          return _canExerciseOption();
        }
        
      return block.timestamp > rolloverTime + 1 days;
    }
    

    /**
    * @notice the function that the vault will call when the round is over. This will redeem/withdraw the FIRB, 
    *         settle the vault in Opyn if in short position or redeem the options if long.
    * . There are 2 main risks involved in this strategy:
    * 1. If the option expired OTM, then all the collateral is returned to this action. If not, some portion of the collateral is deducted 
    * by the Opyn system. 
    * 2. If the option expired ITM, then the options is redeemed/cash settled. if not there is zero payout on the options. 
    */
    function closePosition() external override onlyVault {
      require(canClosePosition(), "Cannot close position");

      if (position == Position.Long){
          if (_canSettleVault()) {
            // get back usdc from settlement
            _settleGammaVault();
          }
      } 
      if (position == Position.Short){
          require(otoken[0] != address(0), "position is closed");
          require(_canExerciseOption(), "options not expired");
          if(__isOtokenWorthy(otoken[0])){
            _redeemoptions(otoken[0]);
          }
          if(__isOtokenWorthy(otoken[1])){
            _redeemoptions(otoken[1]);
          }
      }
      _withdrawFirb();
      position = Position.Meh;
      lockedAsset = 0;
      // set action state.
      _setActionIdle();
    }

    /**
    * @notice checks if the current vault can be settled
    */
    function _canSettleVault() internal view returns (bool) {
       require(position == Position.Short);
       if (lockedAsset != 0 && otoken[0] != address(0)) {
           return controller.isSettlementAllowed(otoken[0]);
      }
      return false;
    }

    function _canExerciseOption() internal view returns (bool) {
      require(position == Position.Long, "Not Long!");
      if(otoken[0] != address(0) && otoken[1] == address(0)){
          return IOToken(otoken[0]).expiryTimestamp() < block.timestamp ;
      }else if(otoken[0] != address(0) && otoken[1] != address(0)){
          return IOToken(otoken[0]).expiryTimestamp() < block.timestamp && IOToken(otoken[1]).expiryTimestamp() < block.timestamp ;
      } else {
          return false;
      }
    }

    /**
     * @notice checks if otoken expired worthless
     */
    function __isOtokenWorthy(address _otoken) internal view returns(bool){
        require (_otoken != address(0));
        return controller.getPayout(_otoken, IERC20(_otoken).balanceOf(address(this))) > 0;
    }

    function longViaAirSwap(
        SwapTypes.Order[] memory _order
    ) external {
        require(position == Position.Long);
        _tradeAirSwapOTC(_order);
    }

    /** 
     * @notice Allows owner to mint and sell options. Currently some limitations to this 
     *      strategy are:
     * 1. Once the collateral amount is deposited into the vault, it is not possible to 
     * settle the vault and collect collateral until the FIRB has matured. Temporary fix to this is to 
     * mint shortdated FIRB.
     */
    function shortViaAirSwap(
        uint256[] memory _collateralAmount,
        uint256[] memory _otokenAmount,
        SwapTypes.Order[] memory _order
    ) external {
        require(position == Position.Short, "Invalid positon");

        for(uint i = 0; i < _order.length; i++){
            // require(_collateralAmount[i].mul(MIN_PROFITS).div(BASE) <= _order[i].signer.amount, "Need minimum option premium");
            lockedAsset = lockedAsset.add(_collateralAmount[i]);

            // mint otoken using the util function
            _mintOTokens(asset, _collateralAmount[i], otoken[i], _otokenAmount[i]);
        } 
        _tradeAirSwapOTC(_order);
    }

    function _tradeAirSwapOTC(
        SwapTypes.Order[] memory _order
    ) internal {
        require(_order.length > 0 && _order.length <= 2);
        for(uint i = 0; i < _order.length; i++){
            require(_order[i].sender.wallet == address(this), "!Sender");
            require(_order[i].sender.token == otoken[i], "Can only sell otoken");
            require(_order[i].signer.token == asset, "Can only sell for asset");

            _fillAirswapOrder(_order[i]);
        }  
    }

    /**
     * @notice this mints a firb and sets the position of the vault
     */
    function mintFirb(uint256 deposit_amt, uint64 mat_timestamp, Position _position) external {
      require(_position != Position.Meh);
      require(position == Position.Meh);
      uint256 amountDepositedin88mph = _mintFirb(deposit_amt, mat_timestamp);
      lockedAsset += amountDepositedin88mph;

      position = _position;
    }

    /**
     * @notice redeem options on opyn
     */
    function _redeemoptions(address _otoken) internal {
        _redeemOTokens(_otoken, IERC20(_otoken).balanceOf(address(this)));
    }

    /**
     * @notice Currently the owner is left to decide how to linearly withdraw and vested mph (preferably to USDC)
     */
    function swapVestedMph(address _to) external {
      _withdrawAndSwapVestedMph(_to);
    }

    /**
     * @notice uniswap wildcard
     */
    function swap(address from, address to, uint256 amount) external {
      _swap(from, to, amount);
    }

}
