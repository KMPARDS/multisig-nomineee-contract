pragma solidity ^0.7.0;
// ["0x4B0897b0513fdC7C541B6d9D7E929C4e5364D2dB","0x583031D1113aD414F02576BD6afaBfb302140225","0xdD870fA1b7C4700F2BD7f44238821C26f7392148"]
// ["0x8701D9EBF337813C895e014D0534a283Ef1946C6", "0x5AA35C450B9bd849B6E43EB9846EF7BB688abcAF", "0x490c0735803cd3618dD7dd042257AE66a2061fe1"]
contract MultiSigWallet {

    /*
     *  Events
     */
    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event Approval(uint indexed transaction);
    event Deposit(address indexed sender, uint value);
    event NomineeAddition(address indexed nominee);
    event NomineeRemoval(address indexed nominee);
    event RequirementChange(uint8 requiredP);
    event NomineeModeChanged(address indexed sender, uint indexed time);
    event PermissionGranted(address indexed sender, uint indexed time);
    event PermissionFailed(address indexed sender, uint indexed time);
    event OwnershipTransffered(address indexed from, address indexed to);

    /*
     *  Constants
     */
    uint constant public MAX_OWNER_COUNT = 50;

    /*
     *  Storage
     */
    struct Transaction {
        address destination;
        uint value;
        uint timestamp;
        bytes data;
        bool executed;
    }
    
    Transaction[] public transactions;
    mapping (uint => mapping (address => bool)) public confirmations;
    mapping (uint => mapping (address => bool)) public pendingConfirmations;
    mapping (address => bool) public isNominee;   //isNominee = false for owner
    mapping (address => uint8) public voteMultiplier;
    address[] public nominees; 
    address public owner;
    address public appointee;
    uint public required;
    uint public requiredP;
    uint public transactionCount;
    uint public totalVotes;
    bool public nomineeMode;
    bool public isGrantedPermission;
    bool public isOwnerDeceased;
    

    /*
     *  Modifiers
     */
    modifier onlyWallet() {
        require(msg.sender == address(this),"Access denied");
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner,"Access denied");
        _;
    }

    modifier onlyNominee() {
        require(isNominee[msg.sender],"Access denied");
        _;
    }
    
    modifier onlyAppointee() {
        require(msg.sender==appointee,"Access denied");
        _;
    }
    
    modifier isOwner(address a){
        require(a==owner,"Access denied");
        _;
    }
    
    modifier nomineeDoesNotExist(address nominee) {
        if(nominee!=owner)
            require(!isNominee[nominee],"Nominee already exists");
        _;
    }

    modifier nomineeExists(address nominee) {
        if(nominee!=owner)
            require(isNominee[nominee],"Nominee doesn't exist");
        _;
    }
    modifier nomineeModeOn(){
        require(nomineeMode==true||msg.sender==owner||isGrantedPermission==true,"Nominee Mode is turned off");
        _;
    }
    modifier transactionExists(uint transactionId) {
        require(transactions[transactionId].destination != address(0),"Transaction doesn't exist");
        _;
    }

    modifier confirmed(uint transactionId, address nominee) {
        require(confirmations[transactionId][nominee],"Transaction not confirmed yet");
        _;
    }

    modifier notConfirmed(uint transactionId, address nominee) {
        require(!confirmations[transactionId][nominee],"Transaction already confirmed");
        _;
    }

    modifier notExecuted(uint transactionId) {
        require(!transactions[transactionId].executed,"Transaction already executed");
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0),"Empty address sent");
        _;
    }
    
    modifier canChangeOwnership() {
        require(isGrantedPermission==true || msg.sender==appointee,"Permission not granted!");
        _;
    }
    
    modifier validRequirement(uint ownerCount, uint8 _requiredP)
    {
        require(ownerCount <= MAX_OWNER_COUNT
            //&& requiredP <= 100
            //&& 0 < requiredP
            && ownerCount != 0,"Invalid requirement");
        _;
    }

    function validateRequirement(uint ownerCount) internal pure{
        require(ownerCount <= MAX_OWNER_COUNT
            && ownerCount != 0,"Invalid requirement");
        //change this code
    }

    // @dev Fallback function allows to deposit ether.
    fallback() payable external
    {
        depositToken();
    }

    /*
     * Public functions
     */
    
    constructor(address _owner, address[] memory _nominees, address _appointee,uint8[] memory _voteMultiplier, uint8 _requiredP)
    validRequirement(_nominees.length,_requiredP)
    {
        require(_nominees.length==_voteMultiplier.length,"Add corresponding vote multiplier for each nominee");
        //validateRequirement(_nominees.length, _requiredP);
        owner = _owner;
        appointee=_appointee;
        isNominee[_owner]=false;
        nomineeMode=false;
        isGrantedPermission=false;
        for (uint i=0; i<_nominees.length; i++) {
            require(!isNominee[_nominees[i]] && _nominees[i] != address(0));
            isNominee[_nominees[i]] = true;
            voteMultiplier[_nominees[i]]=_voteMultiplier[i];
        }
        nominees = _nominees;
        requiredP = _requiredP;
        isOwnerDeceased=false;
        findTotalVotes();
        findRequirement();
    }

    function depositToken() payable public{
        if(msg.value > 0)
            emit Deposit(msg.sender,msg.value);
    }

    // @dev Allows to add a new owner. Tran+saction has to be sent by wallet.
    // @param owner Address of new owner.
    function addNominee(address nominee, uint8 _voteMultiplier)
        public
        onlyOwner()
        nomineeDoesNotExist(nominee)
        notNull(nominee)
    {
        validateRequirement(nominees.length + 1);
        isNominee[nominee] = true;
        nominees.push(nominee);
        voteMultiplier[nominee]=_voteMultiplier;
        isNominee[nominee] = true;

        emit NomineeAddition(nominee);
        findTotalVotes();
        findRequirement();
    }

    // @dev Allows to remove an owner. Transaction has to be sent by wallet.
    // @param owner Address of owner.
    function removeNominee(address nominee)
        public
        onlyOwner()
        nomineeExists(nominee)
    {
        isNominee[nominee] = false;
        for (uint i=0; i<nominees.length - 1; i++)
            if (nominees[i] == nominee) {
                nominees[i] = nominees[nominees.length - 1];
                break;
            }
        //owners.length -= 1;
        // need not use above version for newer versions
        if (required > nominees.length)
            changeRequirement(uint8(nominees.length));
        emit NomineeRemoval(nominee);
    }

    // @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    // @param owner Address of owner to be replaced.
    // @param newOwner Address of new owner.
    function replaceNominee(address nominee, address newNominee)
        public
        onlyOwner() 
        nomineeExists(nominee)
        nomineeDoesNotExist(newNominee)
    {
        for (uint i=0; i<nominees.length; i++)
            if (nominees[i] == nominee) {
                nominees[i] = newNominee;
                break;
            }
        isNominee[nominee] = false;
        isNominee[newNominee] = true;
        emit NomineeRemoval(nominee);
        emit NomineeAddition(newNominee);
    }

    // @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    // @param _required Number of required confirmations.
    function changeRequirement(uint8 _requiredP)
        public
        onlyOwner()
        validRequirement(nominees.length, _requiredP)
    {
        requiredP = _requiredP;
        findTotalVotes();
        findRequirement();
        emit RequirementChange(_requiredP);
    }

    // Allows an owner to submit and confirm a transaction.
    // @param destination Transaction target address.
    // @param value Transaction ether value.
    // @param data Transaction data payload.
    // @return Returns transaction ID.
    function submitTransaction(address destination, uint value, bytes memory data)
        public
        nomineeModeOn()
        returns (uint transactionId)
    {
        transactionId = addTransaction(destination, value, data);
        confirmTransaction(transactionId);
    }

    // @dev Allows an owner to confirm a transaction.
    // @param transactionId Transaction ID.
    // modify to make final verification from Owner
    function confirmTransaction(uint transactionId)
        public
        nomineeExists(msg.sender)
        transactionExists(transactionId)
        nomineeModeOn()
        notConfirmed(transactionId, msg.sender)
    {
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    // @dev Allows an owner to revoke a confirmation for a transaction.
    // @param transactionId Transaction ID.
    function revokeConfirmation(uint transactionId)
        public
        nomineeExists(msg.sender)
        confirmed(transactionId, msg.sender)
        nomineeModeOn()
        notExecuted(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        emit Revocation(msg.sender, transactionId);
    }

    // @dev Allows anyone to execute a confirmed transaction.
    // @param transactionId Transaction ID.
    function executeTransaction(uint transactionId)
        public
        onlyOwner
        notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            (bool result, )=txn.destination.call{value: txn.value}(txn.data);
            if (result)
                emit Execution(transactionId);
            else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }

        }
    }

    function rejectTransaction(uint transactionId)
        public
        onlyOwner
        notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            emit ExecutionFailure(transactionId);
            Transaction storage txn = transactions[transactionId];
            txn.executed = false;
        }
    }


    // @dev Returns the confirmation status of a transaction.
    // @param transactionId Transaction ID.
    // @return Confirmation status.
    function isConfirmed(uint transactionId)
        public
        view
        returns (bool)
    {
        uint count = 0;
        for (uint i=0; i<nominees.length; i++) {
            if (confirmations[transactionId][nominees[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    function changeMultiplier(address a, uint8 m) 
        public onlyOwner
    {
        voteMultiplier[a]=m;
        findTotalVotes();
        findRequirement();
    }

    function changeOwnerToDeceased()
        public onlyAppointee()
    {
        require(isOwnerDeceased==false,"Owner already deceased!");
        isOwnerDeceased=true;
        
    }

    /*
     * Internal functions
     */
    // @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    // @param destination Transaction target address.
    // @param value Transaction ether value.
    // @param data Transaction data payload.
    // @return Returns transaction ID.
    function findTotalVotes()
        internal
    {
        uint i;
        uint sum=0;
        for(i=0;i<nominees.length;i++)
            sum+=voteMultiplier[nominees[i]];
        totalVotes=sum;
    }
    
    function findRequirement()
        internal
    {
        required=(requiredP*totalVotes)/100;
    }

    function addTransaction(address destination, uint value, bytes memory data)
        internal
        notNull(destination)
        returns (uint transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false,
            timestamp: 0
        });
        transactionCount += 1;
        emit Submission(transactionId);
    }

    /*
     * Web3 call functions
     */
    // @dev Returns number of confirmations of a transaction.
    // @param transactionId Transaction ID.
    // @return Number of confirmations.
    function getContractAddress() public view returns (address){
        return address(this);
    }
    
    function getConfirmationCount(uint transactionId)
        public
        view
        returns (uint count)
    {
        for (uint i=0; i<nominees.length; i++)
            if (confirmations[transactionId][nominees[i]])
                count += 1;
    }

    // @dev Returns total number of transactions after filers are applied.
    // @param pending Include pending transactions.
    // @param executed Include executed transactions.
    // @return Total number of transactions after filters are applied.
    function getTransactionCount(bool pending, bool executed)
        public
        view
        returns (uint count)
    {
        for (uint i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
                count += 1;
    }

    // @dev Returns list of owners.
    // @return List of owner addresses.
    function getNominees()
        public
        view
        returns (address[] memory)
    {
        return nominees;
    }
    function grantPermission(uint timeNow,uint timeThen)
        public
    {
        if(timeNow - timeThen == 31536000){
            isGrantedPermission=true;
            emit PermissionGranted(msg.sender,timeNow);
        }
        else{
            isGrantedPermission=false;
            emit PermissionFailed(msg.sender,timeNow);
        }
    }
    function transferOwnership(address originalOwner, address newOwner)
        public
        canChangeOwnership()
    {
        require(newOwner != owner, "Owner already exists");
        isGrantedPermission=false;
        emit OwnershipTransffered(originalOwner,newOwner);
    }
        
    function switchNomineeMode(uint t)
        public
        onlyOwner()
    {
        nomineeMode= ! nomineeMode;
        emit NomineeModeChanged(msg.sender,t);
    }
    

    // @dev Returns array with owner addresses, which confirmed transaction.
    // @param transactionId Transaction ID.
    // @return Returns array of owner addresses.
    function getConfirmations(uint transactionId)
        public
        view
        returns (address[] memory _confirmations)
    {
        address[] memory confirmationsTemp = new address[](nominees.length);
        uint count = 0;
        uint i;
        for (i=0; i<nominees.length; i++)
            if (confirmations[transactionId][nominees[i]]) {
                confirmationsTemp[count] = nominees[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    // @dev Returns list of transaction IDs in defined range.
    // @param from Index start position of transaction array.
    // @param to Index end position of transaction array.
    // @param pending Include pending transactions.
    // @param executed Include executed transactions.
    // @return Returns array of transaction IDs.
    function getTransactionIds(uint from, uint to, bool pending, bool executed)
        public
        view
        returns (uint[] memory _transactionIds)
    {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
            {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](to - from);
        for (i=from; i<to; i++)
            _transactionIds[i - from] = transactionIdsTemp[i];
    }
 