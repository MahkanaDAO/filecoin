// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";

contract ProofHistory {
    enum ProofStatus { UNVERIFIED, ACCEPTED, REJECTED }
    enum ProofKind { UNKNOWN, POREP, POST }
    struct Proof {
        address node;
        uint sector;
        string commR;
        uint proofNum;
        string proofBytes;
        ProofStatus status;
        ProofKind kind;
    }

    address owner;
    
    uint public unverifiedPoRepCount;
    mapping(string => Proof) public poReps;
    mapping(string => Proof) public poSts;
    mapping(address => uint)[24] public hourlyCommitments;

    event poRepSubmission(address node);
    event poStSubmission(address node, uint day, uint hour);

    constructor(address[][24] memory dailySchedule) {
        owner = msg.sender;
        for (uint i = 0; i < dailySchedule.length; i++) {
            for (uint j = 0; j < dailySchedule[i].length; j++) {
                address node = dailySchedule[i][j];
                hourlyCommitments[i][node]++;

                uint sectorID = hourlyCommitments[i][node];
                string memory key = getPoRepKey(node, sectorID);
                poReps[key] = Proof(node, sectorID, "", 0, "", ProofStatus.UNVERIFIED, ProofKind.POREP);
            }
        }
        unverifiedPoRepCount = 24 * dailySchedule[0].length;
    }

    function recordPoRepSubmission(address node, uint[] memory sectors, string[] memory commRs, uint[] memory nums, string[] memory contents) external {
        recordProofSubmission(node, 0, 0, sectors, commRs, nums, contents, ProofKind.POREP);        
        emit poRepSubmission(node);
    }

    function recordPoStSubmission(address node, uint day, uint hour, uint[] memory sectors, string[] memory commRs, uint[] memory nums, string[] memory contents) external {
        uint sectorCount = hourlyCommitments[hour][node];
        require(sectors.length == sectorCount, "number of committed sectors for the hour don't match number of submitted proofs");
        
        recordProofSubmission(node, day, hour, sectors, commRs, nums, contents, ProofKind.POST);
        emit poStSubmission(node, day, hour);
    }

    function recordProofSubmission(
        address node, 
        uint day, 
        uint hour, 
        uint[] memory sectors, 
        string[] memory commRs, 
        uint[] memory nums, 
        string[] memory contents,
        ProofKind kind
    ) private {
        require(msg.sender == owner, "unauthorized caller");
        require(sectors.length == commRs.length, "sectors and commRs have to be the same length");
        require(sectors.length == nums.length, "sectors and proof numbers have to be the same length");
        require(sectors.length == contents.length, "sectors and proof bytes have to be the same length");

        for (uint i = 0; i < sectors.length; i++) {
            string memory key = getProofKey(node, day, hour, sectors[i], kind);
            poSts[key] = Proof(node, sectors[i], commRs[i], nums[i], contents[i], ProofStatus.UNVERIFIED, kind);
            console.log(node, day, hour, sectors[i]);
            console.log(key);
        }
    }

    function acceptPoReps(address node, uint[] memory sectors) external {
        for (uint i = 0; i < sectors.length; i++) {
            string memory key = getPoRepKey(node, sectors[i]);
            if (poReps[key].status == ProofStatus.UNVERIFIED) {
                unverifiedPoRepCount--;
            }
        }
        setProofStatus(node, 0, 0, sectors, ProofStatus.ACCEPTED, ProofKind.POREP);
    }

    function rejectPoReps(address node, uint[] memory sectors) external {
        setProofStatus(node, 0, 0, sectors, ProofStatus.REJECTED, ProofKind.POREP);
    }

    function acceptPoSts(address node, uint day, uint hour, uint[] memory sectors) external {
        setProofStatus(node, day, hour, sectors, ProofStatus.ACCEPTED, ProofKind.POST);
    }

    function rejectPoSts(address node, uint day, uint hour, uint[] memory sectors) external {
        setProofStatus(node, day, hour, sectors, ProofStatus.REJECTED, ProofKind.POST);
    }

    function setProofStatus(address node, uint day, uint hour, uint[] memory sectors, ProofStatus status, ProofKind kind) private {
        require(msg.sender == owner, "unauthorized caller");
        for (uint i = 0; i < sectors.length; i++) {
            string memory key = getProofKey(node, day, hour, sectors[i], kind);
            poSts[key].status = status;
        }
    }

    function getProofKey(address node, uint day, uint hour, uint sectorID, ProofKind kind) pure private returns (string memory) {
        require(kind != ProofKind.UNKNOWN, "must provide poRep or poSt as proof kind");
        return kind == ProofKind.POREP ? getPoRepKey(node, sectorID) : getPoStKey(node, day, hour, sectorID);
    }

    function getPoRepKey(address node, uint sectorID) pure public returns (string memory) {
        return string.concat(
            Strings.toHexString(uint160(node), 20), 
            "-", 
            Strings.toString(sectorID)
        );
    }

    function getPoStKey(address node, uint day, uint hour, uint sectorID) pure public returns (string memory) {
        return string.concat(
            Strings.toHexString(uint160(node), 20),
            "-",
            Strings.toString(day),
            "-",
            Strings.toString(hour),
            "-",
            Strings.toString(sectorID)
        );
    }
}