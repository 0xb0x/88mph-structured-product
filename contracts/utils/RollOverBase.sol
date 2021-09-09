// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

contract RollOverBase is OwnableUpgradeable {
  address[2] public otoken;
  address[2] public nextOToken;

  uint256 public constant MIN_COMMIT_PERIOD = 18 hours;
  uint256 public commitStateStart;

  enum ActionState {
    // action will go "idle" after the vault close this position, and before the next otoken is committed.
    Idle,
    // onwer already set the next otoken this vault is trading.
    // during this phase, all funds are already back in the vault and waiting for re-distribution
    // users who don't agree with the setting of next round can withdraw.
    Committed,
    // after vault calls "rollover", owner can start minting / buying / selling according to each action.
    Activated
  }

  ActionState public state;

  IWhitelist public opynWhitelist;

  modifier onlyCommitted() {
    require(state == ActionState.Committed, "!COMMITED");
    _;
  }

  modifier onlyActivated() {
    require(state == ActionState.Activated, "!Activated");
    _;
  }

  function _initRollOverBase(address _opynWhitelist) internal {
    state = ActionState.Idle;
    opynWhitelist = IWhitelist(_opynWhitelist);
  }

  /**
   * owner can commit the next otoken, if it's in idle state.
   * or re-commit it if needed during the commit phase.
   * if only one otoken is commited, then the otoken address
   * should be at slot 0 
   * i.e [0xrr6dd6, 0x000000];
   */
  function commitOToken(address[2] memory _nextOToken) external onlyOwner {
    require(state != ActionState.Activated, "Activated");
    _checkOToken(_nextOToken);

    nextOToken[0] = _nextOToken[0];
    nextOToken[1] = _nextOToken[1];

    state = ActionState.Committed;

    commitStateStart = block.timestamp;
  }

  function _setActionIdle() internal onlyActivated {
    // wait for the owner to set the next option
    state = ActionState.Idle;
  }

  function _rollOverNextOTokenAndActivate() internal onlyCommitted {
    require(block.timestamp - commitStateStart > MIN_COMMIT_PERIOD, "COMMIT_PHASE_NOT_OVER");
    
    otoken[0] = nextOToken[0];
    otoken[1] = nextOToken[1];
    nextOToken[0] = address(0);
    nextOToken[1] = address(0);

    state = ActionState.Activated;
  }

  function _checkOToken(address[2] memory _nextOToken) private view {
      require(_nextOToken[0] != address(0),"oToken is zero address");
      require(opynWhitelist.isWhitelistedOtoken(_nextOToken[0]), "!OTOKEN");
      if(_nextOToken[1] != address(0)){
        require(opynWhitelist.isWhitelistedOtoken(_nextOToken[1]), "!OTOKEN");
      }
      _customOTokenCheck(_nextOToken[0]);
      _customOTokenCheck(_nextOToken[1]);
  }

  /**
   * cutom otoken check hook to be overriden by each
   */
  function _customOTokenCheck(address _nextOToken) internal view virtual {}
}
