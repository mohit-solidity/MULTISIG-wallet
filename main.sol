// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
contract MULTISIG{
    uint totalRequests=0;
    uint constant maxOwners=5;
    bool locked;
    address[] private owners;
    address public head;
    struct Request{
        address to;
        address by;
        uint amount;
        uint startTime;
        uint endTime;
        bool executed;
        bool cancelled;
        uint8 totalApprovals;
    }
    mapping(address=>uint) private balance;
    mapping(address=>bool) private isOwner;
    mapping(uint=>Request) private requests;
    mapping(uint=>mapping(address=>bool)) private isApproved;

    event Deposit(address from,uint amount);
    event Withdraw(address from,uint amount);
    event HeadChanged(address from,address to);
    event newOwner(address newowner);
    event OwnerRemoved(address removed);
    event RequestCreated(address to,address from,uint amount,uint starttime,uint time);
    event RequestCancelled(address from,uint index);
    event RequestApproved(address from,uint index,uint totalApprovals);
    event RequestExecuted(address from,uint amount,address to);

    error NotAuthorised();
    error NoReenterant();
    error InvalidAddress();
    error AlreadyOwner();
    error RequestIsCancelled();
    error InvalidIndex();
    error AlreadyApproved();
    error AlreadyExecuted();
    error DeadlineReached();
    error NotEnoughBalance();

    constructor(){
        owners.push(msg.sender);
        head = msg.sender;
        isOwner[msg.sender] = true;
    }
    modifier onlyOwners{
        if(!isOwner[msg.sender]) revert NotAuthorised();
        _;
    }
    modifier onlyHead{
        if(msg.sender!=head) revert NotAuthorised();
        _;
    }
    modifier noReenterancy{
        if(locked) revert NoReenterant();
        locked = true;
        _;
        locked = false;
    }
    function changeHead(address newHead) public onlyHead{
        if(newHead==address(0)) revert InvalidAddress();
        require(isOwner[newHead],"New Head Must Be An Owner");
        head = newHead;
        emit HeadChanged(msg.sender,newHead);
    }
    function addOwner(address _newOwner) public onlyOwners onlyHead{
        require(owners.length<maxOwners,"Max Owners Reached");
        if(isOwner[_newOwner]) revert AlreadyOwner();
        if(_newOwner==address(0)) revert InvalidAddress();
        isOwner[_newOwner] = true;
        owners.push(_newOwner);
        emit newOwner(_newOwner);
    }
    function removeOwner(address Owner) public onlyOwners onlyHead{
        if(Owner==address(0)) revert InvalidAddress();
        require(isOwner[Owner],"Not A Owner");
        isOwner[Owner] = false;
        for(uint i=0;i<owners.length;i++){
            if(Owner == owners[i]){
                owners[i] = owners[owners.length-1];
                owners.pop();
                break;
            }
        }
        emit OwnerRemoved(Owner);
    }
    function deposit() public payable {
        require(msg.value>0 ether,"Must Be Greater Than 0 ETHER");
        balance[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    function makeRequest(address to,uint amount,uint deadline_DAYS) public onlyOwners{
        requests[totalRequests] = Request(to,msg.sender,amount,block.timestamp,block.timestamp+deadline_DAYS*1 days,false,false,0);
        totalRequests++;
        emit RequestCreated(to,msg.sender, amount, block.timestamp,block.timestamp + (deadline_DAYS*1 days));
    }
    function approveRequest(uint index) public onlyOwners{
        if(isApproved[index][msg.sender]) revert AlreadyApproved();
        if(index>=totalRequests) revert InvalidIndex();
        Request storage req = requests[index];
        if(req.cancelled) revert RequestIsCancelled();
        if(req.endTime<=block.timestamp) revert DeadlineReached();
        isApproved[index][msg.sender] = true;
        req.totalApprovals++;
        emit RequestApproved(msg.sender, index, req.totalApprovals);
    }
    function cancelRequest(uint index) public onlyOwners{
        if(index>=totalRequests) revert InvalidIndex();
        Request storage req = requests[index];
        if(req.executed) revert AlreadyExecuted();
        if(req.cancelled) revert RequestIsCancelled();
        require(msg.sender==req.by||msg.sender==head,"Only Request created By Owner Or Head Can Cancel The Request");
        req.cancelled = true;
        emit RequestCancelled(msg.sender, index);
        delete requests[index];
    }
    function executeRequest(uint index) public onlyOwners noReenterancy{
        if(index>=totalRequests) revert InvalidIndex();
        Request storage req = requests[index];
        if(req.amount>address(this).balance) revert NotEnoughBalance();
        if(req.cancelled) revert RequestIsCancelled();
        if(req.endTime<=block.timestamp) revert DeadlineReached();
        require(req.totalApprovals>=(owners.length/2)+1,"Not Enough Approvals");
        if(req.executed) revert AlreadyExecuted();
        req.executed = true;
        (bool success, ) = payable(req.to).call{value : req.amount}("");
        require(success,"Transaction Failed");
        emit RequestExecuted(msg.sender, req.amount, req.to);
        delete requests[index];
    }
    function seeOwners() public view returns(address[] memory) {
        return owners;
    }
    function seeRequests(uint index) public view returns(address,address,uint,uint,uint,uint,bool){
        if(index>=totalRequests) revert InvalidIndex();
        Request memory req = requests[index];
        return(req.to,req.by,req.amount,req.startTime,req.endTime,req.totalApprovals,req.executed);
    }
    function getTotalRequests() public view returns(uint){
        return totalRequests;
    }
    receive() external payable { }
}
