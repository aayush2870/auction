// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract Auction {
    struct Product {
        uint256 price;
        address owner;
        bool forsale;
        address previousowner;
    }

    mapping(uint256 => Product) public products;
    mapping(uint256 => address) public highestBidder;
    mapping(uint256 => uint256) public highestBid;
    mapping(uint256 => mapping(address => uint256)) public userBids;
    mapping(uint256 => mapping(address => uint256)) public pendingReturns;
    mapping(uint256 => uint256) public totalBids;

    address[] public registeredUsers;
    uint256 public userCount;

    modifier onlyRegistered() {
        bool isRegistered = false;
        for (uint256 i = 0; i < registeredUsers.length; i++) {
            if (registeredUsers[i] == msg.sender) {
                isRegistered = true;
                break;
            }
        }
        require(isRegistered, "User not registered");
        _;
    }

    modifier onlyOwner(uint256 _productId) {
        require(products[_productId].owner == msg.sender, "Not the product owner");
        _;
    }

    function registerUser() public {
        require(userCount < 10, "only 10 users can register");
        for (uint256 i = 0; i < registeredUsers.length; i++) {
            require(registeredUsers[i] != msg.sender, "User already registered");
        }
        // Check if the user is an owner of any product
        for (uint256 i = 0; i < userCount; i++) {
            require(products[i].owner != msg.sender, "Owners cannot register as users");
        }
        registeredUsers.push(msg.sender);
        userCount++;
    }

    function addProduct(
        uint256 _id,
        uint256 _price,
        address _owner,
        bool _forsale,
        address _previousowner
    ) public {
        // Ensure the old owner cannot add the same product with the same ID
        if (products[_id].owner != address(0)) {
            require(
                products[_id].previousowner != msg.sender,
                "Previous owner cannot re-add the same product"
            );
        }

        Product memory newProduct = Product({
            price: _price * 1 ether,
            owner: _owner,
            forsale: _forsale,
            previousowner: _previousowner
        });

        products[_id] = newProduct;
    }

    function bid(uint256 _productId) public payable onlyRegistered {
        Product storage product = products[_productId];
        require(product.forsale, "Auction not active");
        require(msg.sender != product.owner, "Owner can't bid on their product");

        uint256 currentTotalBid = userBids[_productId][msg.sender] + msg.value;
        uint256 minimumBid = highestBid[_productId] > product.price ? highestBid[_productId] : product.price;
        require(currentTotalBid > minimumBid, "Total bid must be higher than the current highest bid");

        // Refund the previous highest bidder if applicable
        if (highestBid[_productId] != 0) {
            pendingReturns[_productId][highestBidder[_productId]] += highestBid[_productId];
        }

        // Update user’s total bid and highest bid
        userBids[_productId][msg.sender] = currentTotalBid;
        highestBidder[_productId] = msg.sender;
        highestBid[_productId] = currentTotalBid;
        
        // Increment total bid count
        totalBids[_productId]++;
    }

    function endAuction(uint256 _productId) public {
        Product storage product = products[_productId];
        require(product.owner == msg.sender, "Only the owner can end the auction");
        require(product.forsale, "Auction already ended");

        product.forsale = false;

        if (highestBid[_productId] != 0) {
            // Transfer the highest bid to the product owner
            (bool success, ) = payable(product.owner).call{value: highestBid[_productId]}("");
            require(success, "Failed to transfer highest bid");

            // Update product ownership and price
            product.previousowner = product.owner;
            product.owner = highestBidder[_productId];
            product.price = highestBid[_productId];
            product.forsale = true; // Automatically put the product for sale

            // Refund all non-winning bids
            for (uint256 i = 0; i < registeredUsers.length; i++) {
                address user = registeredUsers[i];
                if (user != highestBidder[_productId]) {
                    uint256 amount = userBids[_productId][user];
                    if (amount > 0) {
                        userBids[_productId][user] = 0;
                        (bool refundSuccess, ) = payable(user).call{value: amount}("");
                        if (!refundSuccess) {
                            pendingReturns[_productId][user] = amount;
                        }
                    }
                }
            }
        }
    }

    function cancelAuction(uint256 _productId) public {
        Product storage product = products[_productId];
        require(product.owner == msg.sender, "Only the owner can cancel the auction");
        require(product.forsale, "Auction already ended or not active");

        product.forsale = false;

        // Refund all bids
        for (uint256 i = 0; i < registeredUsers.length; i++) {
            address user = registeredUsers[i];
            uint256 amount = pendingReturns[_productId][user];
            if (amount > 0) {
                pendingReturns[_productId][user] = 0;
                (bool refundSuccess, ) = payable(user).call{value: amount}("");
                if (!refundSuccess) {
                    pendingReturns[_productId][user] = amount;
                }
            }
        }

        // CHECKS IF THE HIGHEST BID IS NOT ZERO
        if (highestBid[_productId] != 0) {
            address highestBidderAddress = highestBidder[_productId];
            uint256 highestBidAmount = highestBid[_productId];

            // Reset highest bid
            highestBid[_productId] = 0;
            highestBidder[_productId] = address(0);

            // Refund the highest bid
            (bool refundSuccess, ) = payable(highestBidderAddress).call{value: highestBidAmount}("");
            if (!refundSuccess) {
                pendingReturns[_productId][highestBidderAddress] = highestBidAmount;
            }
        }
    }

    function updateProduct(
        uint256 _productId,
        uint256 _newPrice,
        bool _forsale
    ) public onlyOwner(_productId) {
        Product storage product = products[_productId];
        product.price = _newPrice * 1 ether;
        product.forsale = _forsale;
    }

    function getProductOwner(uint256 _productId) public view returns (address) {
        return products[_productId].owner;
    }

    function getTotalBids(uint256 _productId) public view returns (uint256) {
        return totalBids[_productId];
    }
}
