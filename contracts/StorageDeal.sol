// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./ProviderRegistry.sol";
import "./ProofHistory.sol";
import "hardhat/console.sol";

// This contract represents one storage deal. A new instance should be deployed on chain for each deal that's brokered.
contract StorageDeal {
    enum Status { PENDING, IN_PROGRESS, COMPLETE }
    struct WorkLog {
        bool isParticipant;
        // This is the number of fulfilled commitments a node has delivered on. 
        // It'll increase over the duration of the storage deal on successful verification of submitted proofs.
        uint fulfillments;
        // This is the total number of commitments a node has promised for the storage deal.
        // The ratio of a node's fulfillments to commitments can be thought of as "what it delivered" compared to "what it promised".
        // This ratio affects the final reward for the node.
        uint commitments;
    }

    address owner;
    address requester;
    // The schedule is a 2D array that describes how the user's data is split amongst the participating nodes in the deal. 
    // The outer array contains 24 inner arrays, one for each hour of the day.
    // An inner array represents how the data is divided between the nodes for the hour.
    // (Each inner array should be the same length, but this will differ for different storage deals based on the user's data size.)
    // If the same node appears in an inner array multiple times, that means it's committed to multiple sectors of the user's data.
    // At the moment, each sector is 512MiB, but this may change in the future.
    //
    // Consider a sample schedule where the user wants to store four sectors of data:
    // Hour of Day    || Sector 1  | Sector 2  | Sector 3  | Sector 4
    // ===============================================================
    // 0 (12AM - 1AM) || node 1    | node 1    | node 1    | node 2
    // 1 (1AM -  2AM) || node 1    | node 2    | node 3    | node 4
    // 2 (2AM -  3AM) || node 2    | node 2    | node 3    | node 4
    // (And so on for the rest of the day...)
    //
    // For the first hour, node1 is storing three of the four sectors and node2 is storing one.
    // If we sum up the commitments for the first three hours, node1: 4, node2: 4, node3 : 2, and node4: 2.
    address[][24] public dailySchedule;
    mapping(address => WorkLog) public participants;

    uint hourlySectorReward;
    uint totalFinalReward;
    uint startDate;
    uint endDate;
    uint dealDays; 
    // Some functions can only be called if the deal has a certain status
    Status public dealStatus;

    ProofHistory public history;
    address verifier;

    /**
     * @param _requester client who wishes to store data with the network
     * @param _startDate timestamp in in *seconds* of the deal's start date
     * @param _endDate timestamp in *seconds* of the deal's end date
     * @param _hourlySectorReward tokens to be paid to each node every hour while deal is ongoing
     * @param _totalFinalReward total tokens to be split and paid to all nodes at end of deal
     * @param _dailySchedule matrix of committed nodes for each hour of the day
     * @param _verifier external contract to validate poRep (proof of replication) and poSts (proof of spacetime)
     */
    constructor (
        address _requester, 
        uint _startDate,
        uint _endDate, 
        uint _hourlySectorReward, 
        uint _totalFinalReward, 
        address[][24] memory _dailySchedule,
        address _verifier
    ) payable {
        owner = msg.sender;
        requester = _requester;
        dailySchedule = _dailySchedule;

        hourlySectorReward = _hourlySectorReward;
        totalFinalReward = _totalFinalReward;
        startDate = _startDate;
        endDate = _endDate;
        dealDays = (endDate - startDate) / 60 / 60 / 24;
    
        dealStatus = Status.PENDING;

        setParticipants();
        history = new ProofHistory(dailySchedule);
        verifier = _verifier;
    }

    function setParticipants() private {
        uint count = getSectorCount();
        for (uint i = 0; i < dailySchedule.length; i++) {
            require(count == dailySchedule[i].length, "number of sectors needs to be the same per hour");
            for (uint j = 0; j < dailySchedule[i].length; j++) {
                address node = dailySchedule[i][j];
                WorkLog storage log = participants[node];
                log.isParticipant = true;
                log.commitments += dealDays;
            }
        }
    }

    function getSectorCount() view public returns (uint) {
        uint count = dailySchedule[0].length;
        require(count > 0, "need at least one sector per hour");
        return count;
    }

    function startDeal() external payable {
        require(msg.sender == requester, "unauthorized caller");
        require(dealStatus == Status.PENDING, "storage deal isn't pending");
        require(history.unverifiedPoRepCount() == 0, "not all proofs of replication have been validated");

        uint totalDailyReward = 24 * hourlySectorReward * getSectorCount();
        uint totalReward = (dealDays * totalDailyReward) + totalFinalReward;
        // TODO we may want to take gas into account too.
        require(msg.value >= totalReward, "insufficient tokens to fund deal");
        console.log(msg.value, totalReward);
        dealStatus = Status.IN_PROGRESS;
    }

    function submitPoReps(uint[] memory sectors, string[] memory commRs, uint[] memory nums, string[] memory contents) external {
        require(dealStatus == Status.PENDING, "storage deal isn't pending");
        history.recordPoRepSubmission(msg.sender, sectors, commRs, nums, contents);
    }

    function submitPoSts(uint[] memory sectors, string[] memory commRs, uint[] memory nums, string[] memory contents) external {
        validateOngoingDeal();
        validateNodeCommitmentToHour(msg.sender);
        history.recordPoStSubmission(msg.sender, getCurrDay(), getCurrHour(), sectors, commRs, nums, contents);
    }

    function validateOngoingDeal() view private {
        require(block.timestamp - startDate <= dealDays * 1 days, "storage deal's end time has passed");
        require(dealStatus == Status.IN_PROGRESS, "storage deal isn't in progress");
    }

    function validateNodeCommitmentToHour(address node) view private {
        require(participants[node].isParticipant, "node isn't a deal participant");
        uint currHour = (block.timestamp / 1000 / 60 seconds / 60 minutes) % 24;
        for (uint j = 0; j < dailySchedule[currHour].length; j++) {
            if (node == dailySchedule[currHour][j]) {
                return;
            }
        }
        require(false, "node isn't committed to the current hour");
    }

    function verifyPoReps(address node, uint[] memory acceptedSectors, uint[] memory rejectedSectors) external {
        require(msg.sender == verifier, "unauthorized caller");
        history.acceptPoReps(node, acceptedSectors);
        history.rejectPoReps(node, rejectedSectors);
    }

    function rewardPoSts(address node, uint currDay, uint currHour, uint[] memory acceptedSectors, uint[] memory rejectedSectors) external {
        require(msg.sender == verifier, "unauthorized caller");

        uint fulfillments = acceptedSectors.length;
        recordFulfillments(node, fulfillments);
        sendHourlyReward(node, fulfillments);
        
        history.acceptPoSts(node, currDay, currHour, acceptedSectors);
        history.rejectPoSts(node, currDay, currHour, rejectedSectors);
    }

    function recordFulfillments(address node, uint fulfillments) private {
        participants[node].fulfillments += fulfillments;
    }

    // TODO instead of paying per hour, we can consider paying per day to save on gas?
    function sendHourlyReward(address node, uint fulfillments) private {
        console.log("sendHourlyReward", fulfillments * hourlySectorReward);
        payable(node).transfer(fulfillments * hourlySectorReward);
    }

    function replaceNode(address oldNode, address newNode) public {
        require(msg.sender == owner, "unauthorized caller");
        validateOngoingDeal();
        for (uint i = 0; i < dailySchedule.length; i++) {
            for (uint j = 0; j < dailySchedule[i].length; j++) {
                if (dailySchedule[i][j] == oldNode) {
                    dailySchedule[i][j] = newNode;
                }
            }
        }
    }

    function endDeal() external {
        // We don't have an assertion that the storage deal's end time has passed
        // because it may be necessary to end the deal early in some cases.
        require(msg.sender == owner, "unauthorized caller");
        require(dealStatus == Status.IN_PROGRESS, "storage deal isn't in progress");
        
        uint totalCommitments = dealDays * 24 * getSectorCount();
        for (uint i = 0; i < dailySchedule.length; i++) {
            for (uint j = 0; j < dailySchedule[i].length; j++) {
                address node = dailySchedule[i][j];
                sendFinalReward(node, totalCommitments);
            }
        }

        // If there are remaining funds, that means either: 
        //  1) the user overpaid up front 
        //  2) or some nodes weren't fully compensated because they didn't fulfill the storage they committed to.
        // We should send these tokens back to the user.
        payable(requester).transfer(address(this).balance);
        dealStatus = Status.COMPLETE;

        // TODO @ygao record the fulfillments and commitments in the node registry.
    }

    // The final reward for each node is based on the fraction of its fulfillments over the total commitments by all nodes.
    function sendFinalReward(address node, uint totalCommitments) private {
        WorkLog storage log = participants[node];
        if (!log.isParticipant) {
            return;
        }
        
        require(log.fulfillments <= log.commitments, "individual fulfillments must be fewer than or equal to individual committments");
        require(log.fulfillments < totalCommitments, "individual fulfillments must be fewer than total commitments");
        payable(node).transfer(totalFinalReward * log.fulfillments / totalCommitments);
        log.isParticipant = false;
    }

    // getCurrDay() and getCurrHour() are helper functions.
    function getCurrDay() view public returns (uint) {
        uint day = block.timestamp / 60 / 60 / 24;
        console.log(block.timestamp, day);
        return day;
    }

    function getCurrHour() view public returns (uint) {
        uint hour = (block.timestamp / 60 / 60) % 24;
        console.log(block.timestamp, hour);
        return hour;
    }
}