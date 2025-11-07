// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReputationRewards with NFT Badges
 * @dev Reputation system with NFT badge minting for Base
 * Users earn reputation points and mint badge NFTs as they progress
 */
contract ReputationRewards {
    
    struct User {
        uint256 reputationPoints;
        uint256 level;
        uint256 lastActionTimestamp;
        uint256 streakDays;
        bool[] unlockedBadges;
        mapping(uint256 => uint256) badgeTokenIds; // badgeId => tokenId
    }
    
    struct Badge {
        string name;
        string description;
        uint256 requiredPoints;
        string tokenURI;
        bool exists;
    }
    
    struct NFTBadge {
        uint256 badgeId;
        address owner;
        uint256 mintedAt;
    }
    
    mapping(address => User) public users;
    mapping(uint256 => Badge) public badges;
    mapping(address => mapping(address => bool)) public hasEndorsed;
    mapping(uint256 => NFTBadge) public nftBadges; // tokenId => NFTBadge
    mapping(uint256 => address) public badgeOwner; // tokenId => owner
    
    uint256 public constant DAILY_BONUS = 10;
    uint256 public constant ENDORSEMENT_POINTS = 25;
    uint256 public constant ACTION_POINTS = 5;
    uint256 public constant STREAK_MULTIPLIER = 2;
    
    uint256 public totalUsers;
    uint256 public badgeCount;
    uint256 public nextTokenId = 1;
    address public owner;
    
    string public name = "Base Reputation Badges";
    string public symbol = "BRB";
    
    event ReputationEarned(address indexed user, uint256 points, string reason);
    event LevelUp(address indexed user, uint256 newLevel);
    event BadgeUnlocked(address indexed user, uint256 badgeId, string badgeName);
    event BadgeNFTMinted(address indexed user, uint256 tokenId, uint256 badgeId);
    event UserEndorsed(address indexed endorser, address indexed endorsed);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        _initializeBadges();
    }
    
    function _initializeBadges() private {
        _createBadge("Newcomer", "Welcome to the Base community!", 0, "ipfs://QmNewcomer");
        _createBadge("Active Member", "Reached 100 reputation points", 100, "ipfs://QmActiveMember");
        _createBadge("Trusted Contributor", "Reached 500 reputation points", 500, "ipfs://QmTrustedContributor");
        _createBadge("Community Leader", "Reached 1000 reputation points", 1000, "ipfs://QmCommunityLeader");
        _createBadge("Legend", "Reached 5000 reputation points", 5000, "ipfs://QmLegend");
    }
    
    function _createBadge(
        string memory _name, 
        string memory description, 
        uint256 requiredPoints,
        string memory tokenURI
    ) private {
        badges[badgeCount] = Badge(_name, description, requiredPoints, tokenURI, true);
        badgeCount++;
    }
    
    function checkIn() external {
        User storage user = users[msg.sender];
        
        if (user.reputationPoints == 0) {
            totalUsers++;
        }
        
        uint256 currentDay = block.timestamp / 1 days;
        uint256 lastActionDay = user.lastActionTimestamp / 1 days;
        
        require(currentDay > lastActionDay, "Already checked in today");
        
        uint256 points = DAILY_BONUS;
        
        // Streak bonus for consecutive check-ins
        if (currentDay == lastActionDay + 1) {
            user.streakDays++;
            points += user.streakDays * STREAK_MULTIPLIER;
        } else {
            user.streakDays = 1;
        }
        
        user.lastActionTimestamp = block.timestamp;
        _addReputation(msg.sender, points, "Daily check-in");
    }
    
    function performAction(string calldata actionName) external {
        require(bytes(actionName).length > 0, "Action name required");
        _addReputation(msg.sender, ACTION_POINTS, actionName);
    }
    
    function endorseUser(address userToEndorse) external {
        require(userToEndorse != msg.sender, "Cannot endorse yourself");
        require(!hasEndorsed[msg.sender][userToEndorse], "Already endorsed");
        require(users[msg.sender].reputationPoints >= 50, "Need 50+ points to endorse");
        
        hasEndorsed[msg.sender][userToEndorse] = true;
        _addReputation(userToEndorse, ENDORSEMENT_POINTS, "Peer endorsement");
        
        emit UserEndorsed(msg.sender, userToEndorse);
    }
    
    function _addReputation(address user, uint256 points, string memory reason) private {
        User storage userProfile = users[user];
        
        if (userProfile.reputationPoints == 0 && userProfile.unlockedBadges.length == 0) {
            userProfile.unlockedBadges = new bool[](badgeCount);
        }
        
        userProfile.reputationPoints += points;
        emit ReputationEarned(user, points, reason);
        
        // Calculate level
        uint256 newLevel = _calculateLevel(userProfile.reputationPoints);
        if (newLevel > userProfile.level) {
            userProfile.level = newLevel;
            emit LevelUp(user, newLevel);
        }
        
        // Check and unlock badges
        _checkBadges(user);
    }
    
    function _calculateLevel(uint256 points) private pure returns (uint256) {
        return (points / 100) + 1;
    }
    
    function _checkBadges(address user) private {
        User storage userProfile = users[user];
        
        for (uint256 i = 0; i < badgeCount; i++) {
            if (!userProfile.unlockedBadges[i] && 
                userProfile.reputationPoints >= badges[i].requiredPoints) {
                userProfile.unlockedBadges[i] = true;
                emit BadgeUnlocked(user, i, badges[i].name);
            }
        }
    }
    
    function mintBadgeNFT(uint256 badgeId) external {
        require(badgeId < badgeCount, "Invalid badge ID");
        User storage user = users[msg.sender];
        require(user.unlockedBadges[badgeId], "Badge not unlocked");
        require(user.badgeTokenIds[badgeId] == 0, "Badge already minted");
        
        uint256 tokenId = nextTokenId++;
        
        nftBadges[tokenId] = NFTBadge({
            badgeId: badgeId,
            owner: msg.sender,
            mintedAt: block.timestamp
        });
        
        badgeOwner[tokenId] = msg.sender;
        user.badgeTokenIds[badgeId] = tokenId;
        
        emit Transfer(address(0), msg.sender, tokenId);
        emit BadgeNFTMinted(msg.sender, tokenId, badgeId);
    }
    
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(badgeOwner[tokenId] != address(0), "Token does not exist");
        NFTBadge memory badge = nftBadges[tokenId];
        return badges[badge.badgeId].tokenURI;
    }
    
    function ownerOf(uint256 tokenId) external view returns (address) {
        address tokenOwner = badgeOwner[tokenId];
        require(tokenOwner != address(0), "Token does not exist");
        return tokenOwner;
    }
    
    function balanceOf(address _owner) external view returns (uint256) {
        require(_owner != address(0), "Invalid address");
        uint256 balance = 0;
        
        for (uint256 i = 1; i < nextTokenId; i++) {
            if (badgeOwner[i] == _owner) {
                balance++;
            }
        }
        
        return balance;
    }
    
    function getUserBadgeTokens(address user) external view returns (uint256[] memory) {
        uint256 balance = 0;
        
        // Count tokens
        for (uint256 i = 1; i < nextTokenId; i++) {
            if (badgeOwner[i] == user) {
                balance++;
            }
        }
        
        // Fill array
        uint256[] memory tokens = new uint256[](balance);
        uint256 index = 0;
        
        for (uint256 i = 1; i < nextTokenId; i++) {
            if (badgeOwner[i] == user) {
                tokens[index] = i;
                index++;
            }
        }
        
        return tokens;
    }
    
    function getUserProfile(address user) external view returns (
        uint256 reputation,
        uint256 level,
        uint256 streak,
        uint256 unlockedBadgesCount,
        uint256 mintedBadgesCount
    ) {
        User storage userProfile = users[user];
        uint256 badgesUnlocked = 0;
        uint256 badgesMinted = 0;
        
        for (uint256 i = 0; i < userProfile.unlockedBadges.length; i++) {
            if (userProfile.unlockedBadges[i]) {
                badgesUnlocked++;
                if (userProfile.badgeTokenIds[i] != 0) {
                    badgesMinted++;
                }
            }
        }
        
        return (
            userProfile.reputationPoints,
            userProfile.level,
            userProfile.streakDays,
            badgesUnlocked,
            badgesMinted
        );
    }
    
    function getBadgeInfo(uint256 badgeId) external view returns (
        string memory _name,
        string memory description,
        uint256 requiredPoints,
        string memory tokenURI
    ) {
        require(badges[badgeId].exists, "Badge does not exist");
        Badge memory badge = badges[badgeId];
        return (badge.name, badge.description, badge.requiredPoints, badge.tokenURI);
    }
    
    function hasUserUnlockedBadge(address user, uint256 badgeId) external view returns (bool) {
        User storage userProfile = users[user];
        if (badgeId >= userProfile.unlockedBadges.length) return false;
        return userProfile.unlockedBadges[badgeId];
    }
    
    function hasUserMintedBadge(address user, uint256 badgeId) external view returns (bool) {
        return users[user].badgeTokenIds[badgeId] != 0;
    }
    
    function addCustomBadge(
        string calldata _name,
        string calldata description,
        uint256 requiredPoints,
        string calldata tokenURI
    ) external onlyOwner {
        _createBadge(_name, description, requiredPoints, tokenURI);
    }
    
    function updateBadgeURI(uint256 badgeId, string calldata newURI) external onlyOwner {
        require(badges[badgeId].exists, "Badge does not exist");
        badges[badgeId].tokenURI = newURI;
    }
    
    // Soulbound: Prevent transfers
    function transferFrom(address, address, uint256) external pure {
        revert("Soulbound: Badge NFTs cannot be transferred");
    }
    
    function safeTransferFrom(address, address, uint256) external pure {
        revert("Soulbound: Badge NFTs cannot be transferred");
    }
    
    function safeTransferFrom(address, address, uint256, bytes memory) external pure {
        revert("Soulbound: Badge NFTs cannot be transferred");
    }
}
