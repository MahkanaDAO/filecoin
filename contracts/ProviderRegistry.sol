// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";

// This contract stores all the nodes that have registered as part of the platform.
// It tracks their history for a reputation system, which should persist between storage deals and incentivize good behavior.
contract ProviderRegistry {
    struct Record {
        // startDate and endDate are timestamps.
        uint startDate;
        uint endDate;
        // startTime and endTime should be between 0-23 and 1-24, respectively.
        uint startTime;
        uint endTime;
        uint storageCapacity;

        bool isActive;
        // If a node has committed to 100 hours for a deal, 50 of the hours have passed, 
        // and the node successfully submitted proofs for 40 of the 50 hours:
        // `fulfilledHours` = 40, `elapsedHours` = 50, so their rating should be 40 / 50 = 80%.
        uint fulfilledHours;
        uint elapsedHours;
        address[] storageDeals;
    }

    mapping(address => Record) public history;
    address owner;

    event weightedRating(address node, uint rating);

    constructor() {
        owner = msg.sender;
    }

    function activateProvider(
        address provider, 
        uint startDate, 
        uint endDate, 
        uint startTime, 
        uint endTime,
        uint storageCapacity
    ) external {
        require(msg.sender == owner, "unauthorized caller");
        history[provider].isActive = true;
        history[provider].startDate = startDate;
        history[provider].endDate = endDate;
        history[provider].startTime = startTime;
        history[provider].endTime = endTime;
        history[provider].storageCapacity = storageCapacity;
    }

    function deactivateProvider(address provider) external {
        require(msg.sender == owner, "unauthorized caller");
        history[provider].isActive = false;
    }

    function setEndDate(address provider, uint endDate) external {
        require(msg.sender == owner, "unauthorized caller");
        require(history[provider].isActive, "inactive node");
        history[provider].endDate = endDate;
    }

    function setStartTime(address provider, uint startTime) external {
        require(msg.sender == owner, "unauthorized caller");
        require(history[provider].isActive, "inactive node");
        history[provider].startTime = startTime;
    }

    function setEndTime(address provider, uint endTime) external {
        require(msg.sender == owner, "unauthorized caller");
        require(history[provider].isActive, "inactive node");
        history[provider].endTime = endTime;
    }

    function setStorageCapacity(address provider, uint storageCapacity) external {
        require(msg.sender == owner, "unauthorized caller");
        require(history[provider].isActive, "inactive node");
        history[provider].storageCapacity = storageCapacity;
    }

    function addStorageDeal(address provider, address deal) external {
        require(msg.sender == owner, "unauthorized caller");
        require(history[provider].isActive, "inactive node");
        history[provider].storageDeals.push(deal);
    }

    function addHours(address provider, uint fulfilledHours, uint elapsedHours) external {
        require(msg.sender == owner, "unauthorized caller");
        require(history[provider].isActive, "node is currently inactive");
        require(fulfilledHours <= elapsedHours, "fulfilled hours must be less than elapsed hours");

        Record storage log = history[provider];
        log.fulfilledHours += fulfilledHours;
        log.elapsedHours += elapsedHours;

        emit weightedRating(provider, (log.fulfilledHours) * 100 * log.fulfilledHours / log.elapsedHours);
    }

    function getRating(address provider) external view returns (uint) {
        Record storage log = history[provider];
        require(log.isActive, "node is currently inactive");
        if (log.elapsedHours == 0) {
            // If the node has no work history yet, we assign a default rating of 90, 
            // which we assume will be the average rating among existing nodes.
            return 90;
        }
        // We have to multiply the rating by 100 because Solidity doesn't allow fractions.
        // This means it'll be an integer between 0 and 100.
        console.log("getRating", log.fulfilledHours, log.elapsedHours);
        return 100 * log.fulfilledHours / log.elapsedHours;
    }

    // Fulfilled hours can be used to weight the rating. 
    // If two storage providers are competing for the same deal and both have a 90% rating, 
    // but one has completed 100 hours and another has completed 200--we favor the one with the higher number.  
    function getFulfilledHours(address provider) external view returns (uint) {
        Record storage log = history[provider];
        require(log.isActive, "node is currently inactive");
        if (log.elapsedHours == 0) {
            // If the node has no work history yet, we return a default of 1, 
            // otherwise the weighted rating will be 0 * 90 = 0.
            return 1;
        }
        return history[provider].fulfilledHours;
    }
}