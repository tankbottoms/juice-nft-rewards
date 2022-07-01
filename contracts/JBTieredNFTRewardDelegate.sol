// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import './abstract/JBNFTRewardDataSource.sol';
import './interfaces/IJBTieredNFTRewardDelegate.sol';

/**
  @title 
  JBTieredLimitedNFTRewardDataSource

  @notice
  Juicebox data source that offers NFTs to project contributors.

  @notice 
  This contract allows project creators to reward contributors with NFTs. 
  Intended use is to incentivize initial project support by minting a limited number of NFTs to the first N contributors among various price tiers.
*/
contract JBTieredLimitedNFTRewardDataSource is JBNFTRewardDataSource, IJBTieredNFTRewardDelegate {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_PRICE_SORT_ORDER(uint256);
  error INVALID_ID_SORT_ORDER(uint256);
  error NOT_AVAILABLE();

  //*********************************************************************//
  // --------------------- internal stored properties ------------------ //
  //*********************************************************************//

  /** 
    @notice
    The reward tiers. 
  */
  JBNFTRewardTier[] internal _tiers;

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /** 
    @notice
    The token to expect contributions to be made in.
  */
  address public immutable override contributionToken;

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /**
    @notice 
    Current supply of tokens minted in each tier.
  */
  mapping(uint256 => uint256) public override tierSupply;

  /** 
    @notice 
    The reward tiers.

    @return The tiers. 
  */
  function tiers() external view override returns (JBNFTRewardTier[] memory) {
    return _tiers;
  }

  /** 
    @notice 
    The total supply of issued NFTs from all tiers.

    @return supply The total number of NFTs between all tiers.
  */
  function totalSupply() external view override returns (uint256 supply) {
    // Keep a reference to the number of tiers.
    uint256 _numTiers = _tiers.length;

    // Keep a reference to the tier being iterated on.
    JBNFTRewardTier memory _tier;

    for (uint256 _i; _i < _numTiers; ) {
      // Set the tier being iterated on.
      _tier = _tiers[_i];

      // Increment the total supply with the amount used already.
      supply += _tier.initialAllowance - _tier.remainingAllowance;

      unchecked {
        ++_i;
      }
    }
  }

  /** 
    @notice 
    The total number of tokens with the given ID.

    @return Either 1 if the token has been minted, or 0 if it hasnt.
  */
  function tokenSupply(uint256 _tokenId) external view override returns (uint256) {
    return _ownerOf[_tokenId] != address(0) ? 1 : 0;
  }

  /** 
    @notice 
    The total number of tokens owned by the given owner. 

    @param _owner The address to check the balance of.

    @return The number of tokens owners by the owner.
  */
  function totalOwnerBalance(address _owner) external view override returns (uint256) {
    return _balanceOf[_owner];
  }

  /** 
    @notice 
    The total number of tokens with the given ID owned by the given owner. 

    @param _owner The address to check the balance of.
    @param _tokenId The ID of the token to check the owner's balance of.

    @return Either 1 if the owner has the token, or 0 if it does not.
  */
  function ownerTokenBalance(address _owner, uint256 _tokenId)
    public
    view
    override
    returns (uint256)
  {
    return _ownerOf[_tokenId] == _owner ? 1 : 0;
  }

  /**
    @param _projectId The ID of the project for which this NFT should be minted in response to payments made. 
    @param _directory The directory of terminals and controllers for projects.
    @param _name The name of the token.
    @param _symbol The symbol that the token should be represented by.
    @param _tokenUriResolver A contract responsible for resolving the token URI for each token ID.
    @param _baseUri The token's base URI, to be used if a URI resolver is not provided. 
    @param _contractUri A URI where contract metadata can be found. 
    @param _expectedCaller The address that should be calling calling the data source.
    @param _owner The address that should own this contract.
    @param _contributionToken The token that contributions are expected to be in terms of.
    @param __tiers The tiers according to which token distribution will be made. 
  */
  constructor(
    uint256 _projectId,
    IJBDirectory _directory,
    string memory _name,
    string memory _symbol,
    IToken721UriResolver _tokenUriResolver,
    string memory _baseUri,
    string memory _contractUri,
    address _expectedCaller,
    address _owner,
    address _contributionToken,
    JBNFTRewardTier[] memory __tiers
  )
    JBNFTRewardDataSource(
      _projectId,
      _directory,
      _name,
      _symbol,
      _tokenUriResolver,
      _baseUri,
      _contractUri,
      _expectedCaller,
      _owner
    )
  {
    contributionToken = _contributionToken;

    // Make sure the tiers were delivered in order.
    if (_tiers.length != 0) {
      _tiers.push(_tiers[0]);

      // Get a reference to the number of tiers.
      uint256 _numTiers = __tiers.length;

      // Keep a reference to the tier being iterated on.
      JBNFTRewardTier memory _tier;

      for (uint256 _i = 1; _i < _numTiers; ) {
        // Set the tier being iterated on.
        _tier = _tiers[_i];

        // Make sure the tier's contribution floor is greater than the previous contribution floor.
        if (_tier.contributionFloor <= __tiers[_i - 1].contributionFloor)
          revert INVALID_PRICE_SORT_ORDER(_i);

        // Make sure the tiers' ID ranges don't collide.
        if (_tier.idCeiling - _tier.remainingAllowance <= __tiers[_i - 1].idCeiling)
          revert INVALID_ID_SORT_ORDER(_i);

        // Set the initial allowance to be the remaining allowance.
        _tier.initialAllowance = _tier.remainingAllowance;

        // Add the tier.
        _tiers.push(_tier);

        unchecked {
          ++_i;
        }
      }
    }
  }

  /** 
    @notice
    Mint a token within the tier for the provided value.

    @dev
    Only a project owner can mint tokens.

    @param _beneficiary The address that should receive to token.
    @param _value The value to mint a token based on.
  */
  function mint(address _beneficiary, uint256 _value)
    external
    override
    onlyOwner
    returns (uint256 tokenId)
  {
    // Get a reference to the tier number.
    uint256 _tierNumber;

    // Keep a reference to the token ID.
    (tokenId, _tierNumber) = _getTokenInfo(_value);

    // Make sure there's a token ID.
    if (tokenId == 0) revert NOT_AVAILABLE();

    // If there's a token to mint, do so and increment the tier supply.
    _mint(_beneficiary, tokenId);
    tierSupply[_tierNumber] += 1;
  }

  /**
    @notice 
    Mints a token for a given contribution to the beneficiary.

    @param _beneficiary The address sending the contribution.
    @param _contribution The contribution amount.
   */
  function _processContribution(address _beneficiary, JBTokenAmount calldata _contribution)
    internal
    override
  {
    // Make the contribution is being made in the expected token.
    if (_contribution.token != contributionToken) return;

    // Keep a reference to the token ID.
    (uint256 _tokenId, uint256 _tierNumber) = _getTokenInfo(_contribution.value);

    // Make sure there's a token ID.
    if (_tokenId == 0) revert NOT_AVAILABLE();

    // If there's a token to mint, do so and increment the tier supply.
    _mint(_beneficiary, _tokenId);
    tierSupply[_tierNumber] += 1;
  }

  /** 
    @notice
    Finds the token ID and tier given a contribution amount. 

    @param _amount The amount of the contribution.

    @return tokenId The ID of the token.
    @return tierNumber The tier number.
  */
  function _getTokenInfo(uint256 _amount) internal returns (uint256 tokenId, uint256 tierNumber) {
    // Keep a reference to the number of tiers.
    uint256 _numTiers = _tiers.length;

    // Keep a reference to the tier being iterated on.
    JBNFTRewardTier memory _tier;

    for (uint256 _i; _i < _numTiers; ) {
      // Set the tier being iterated on.
      _tier = _tiers[_i];

      // If the contribution value is at least as much as the floor
      if (
        _tier.contributionFloor <= _amount &&
        (_i == _numTiers - 1 || _tiers[_i + 1].contributionFloor > _amount) &&
        _tier.remainingAllowance != 0
      ) {
        // The token ID incrementally increases until the id cieling.
        tokenId = _tier.idCeiling - _tier.remainingAllowance;

        // Decrement the reminaing allowance of tokens for this tier.
        unchecked {
          --_tiers[_i].remainingAllowance;
        }

        // The the tier being returned, which is the 1 indexed position in the tiers array.
        tierNumber = _i + 1;

        // Break out of the for loop since we've found the right tier.
        return (tokenId, tierNumber);
      }

      unchecked {
        ++_i;
      }
    }
  }
}
