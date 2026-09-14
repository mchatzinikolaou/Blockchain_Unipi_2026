// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CertificatesManager
 * @dev Manages the issuance, verification, and revocation of digital certificates.
 * Fully aligned with the .NET Backend API Contract.
 */
contract CertificatesManager {

    // ==========================================
    // ENUMS
    // ==========================================
    enum UserRole { Admin, Issuer, Holder, Verifier, RevocationOfficer, Auditor }
    enum CertificateType { Seminar, Professional, Academic, License }
    enum CertificateStatus { Active, Expired, Revoked }

    // ==========================================
    // STRUCTS
    // ==========================================
    struct User {
        address userAddress;
        string name; 
        UserRole role;
        bool active;
    }

    struct Certificate {
        string certificateId;
        CertificateType certType;
        address issuer;
        address holder;
        string fileHash;
        uint256 issueDate;
        uint256 expiryDate;
        CertificateStatus status;
        bool revoked;
        string revocationReason;
    }

    // ==========================================
    // STATE VARIABLES & MAPPINGS
    // ==========================================
    mapping(address => User) public users;
    mapping(string => Certificate) private certificates;
    
    // Helper mappings for quick lookups
    mapping(string => string) private hashToCertId; 
    mapping(address => string[]) private holderCertificates;
    mapping(address => string[]) private issuerCertificates; 
    
    string[] public allCertificateIds; 
    
    uint256 public totalIssued;
    uint256 public totalRevoked;

    // ==========================================
    // EVENTS
    // ==========================================
    event UserRegistered(address indexed userAddress, UserRole role, string name);
    event UserRoleUpdated(address indexed userAddress, UserRole newRole);
    event UserDeactivated(address indexed userAddress);
    event UserReactivated(address indexed userAddress);
    
    event CertificateIssued(string indexed certificateId, address indexed issuer, address indexed holder, string fileHash);
    event CertificateRevoked(string indexed certificateId, address indexed revocationOfficer, string reason);
    event CertificateVerified(string indexed certificateId, address indexed verifier);

    // ==========================================
    // MODIFIERS
    // ==========================================
    modifier onlyActiveUser() {
        require(users[msg.sender].active, "User is not active or not registered.");
        _;
    }

    modifier onlyAdmin() {
        require(users[msg.sender].role == UserRole.Admin, "Access denied: Requires Admin role.");
        _;
    }

    modifier onlyIssuer() {
        require(users[msg.sender].role == UserRole.Issuer, "Access denied: Requires Issuer role.");
        _;
    }

    modifier onlyRevocationOfficer() {
        require(users[msg.sender].role == UserRole.RevocationOfficer, "Access denied: Requires Revocation Officer role.");
        _;
    }

    modifier onlyVerifier() {
        require(users[msg.sender].role == UserRole.Verifier, "Access denied: Requires Verifier role.");
        _;
    }

    modifier onlyAuditor() {
        require(users[msg.sender].role == UserRole.Auditor, "Access denied: Requires Auditor role.");
        _;
    }

    // ==========================================
    // CONSTRUCTOR
    // ==========================================
    constructor() {
        // Deployer becomes the initial Admin
        users[msg.sender] = User({
            userAddress: msg.sender,
            name: "System Admin",
            role: UserRole.Admin,
            active: true
        });
        emit UserRegistered(msg.sender, UserRole.Admin, "System Admin");
    }

    // ==========================================
    // USER MANAGEMENT (ADMIN ENDPOINTS)
    // ==========================================
    
    // API: POST admin/createIssuer (and general register)
    function registerUser(address _userAddress, string memory _name, UserRole _role) public onlyActiveUser onlyAdmin {
        require(!users[_userAddress].active, "User already exists and is active.");
        users[_userAddress] = User({
            userAddress: _userAddress,
            name: _name,
            role: _role,
            active: true
        });
        emit UserRegistered(_userAddress, _role, _name);
    }

    // API: PUT admin/setRoles/{userId}
    function updateUserRole(address _userAddress, UserRole _newRole) public onlyActiveUser onlyAdmin {
        require(users[_userAddress].active, "User does not exist or is inactive.");
        users[_userAddress].role = _newRole;
        emit UserRoleUpdated(_userAddress, _newRole);
    }

    // API: DELETE admin/deleteUser/{userId}
    function deactivateUser(address _userAddress) public onlyActiveUser onlyAdmin {
        require(users[_userAddress].active, "User is already inactive.");
        users[_userAddress].active = false;
        emit UserDeactivated(_userAddress);
    }

    // API: PUT admin/reactivateUser/{userId}
    function reactivateUser(address _userAddress) public onlyActiveUser onlyAdmin {
        require(users[_userAddress].userAddress != address(0), "User does not exist.");
        require(!users[_userAddress].active, "User is already active.");
        users[_userAddress].active = true;
        emit UserReactivated(_userAddress);
    }

    // ==========================================
    // CERTIFICATE MANAGEMENT
    // ==========================================

    // API: POST issuer/createCertificate
    function issueCertificate(
        string memory _certificateId,
        CertificateType _certType,
        address _holder,
        string memory _fileHash,
        uint256 _expiryDate
    ) public onlyActiveUser onlyIssuer {
        require(bytes(certificates[_certificateId].certificateId).length == 0, "Certificate ID already exists.");
        require(bytes(hashToCertId[_fileHash]).length == 0, "A certificate with this file hash already exists.");

        certificates[_certificateId] = Certificate({
            certificateId: _certificateId,
            certType: _certType,
            issuer: msg.sender,
            holder: _holder,
            fileHash: _fileHash,
            issueDate: block.timestamp,
            expiryDate: _expiryDate,
            status: CertificateStatus.Active,
            revoked: false,
            revocationReason: ""
        });

        // Update lookups
        hashToCertId[_fileHash] = _certificateId;
        holderCertificates[_holder].push(_certificateId);
        issuerCertificates[msg.sender].push(_certificateId);
        allCertificateIds.push(_certificateId);
        
        totalIssued++;

        emit CertificateIssued(_certificateId, msg.sender, _holder, _fileHash);
    }

    // API: POST revocation/revokeCertificate/{certificateId}
    function revokeCertificate(string memory _certificateId, string memory _reason) public onlyActiveUser onlyRevocationOfficer {
        require(bytes(certificates[_certificateId].certificateId).length != 0, "Certificate does not exist.");
        require(!certificates[_certificateId].revoked, "Certificate is already revoked.");

        certificates[_certificateId].revoked = true;
        certificates[_certificateId].status = CertificateStatus.Revoked;
        certificates[_certificateId].revocationReason = _reason;

        totalRevoked++;
        emit CertificateRevoked(_certificateId, msg.sender, _reason);
    }

    // API: POST verify/{certificateId}
    function verifyCertificateById(string memory _certificateId) public onlyActiveUser onlyVerifier returns (
        CertificateType certType,
        address issuer,
        address holder,
        uint256 issueDate,
        uint256 expiryDate,
        CertificateStatus status,
        string memory revocationReason
    ) {
        require(bytes(certificates[_certificateId].certificateId).length != 0, "Certificate not found.");
        
        Certificate storage cert = certificates[_certificateId];
        
        // Dynamically check expiry
        CertificateStatus currentStatus = cert.status;
        if (!cert.revoked && cert.expiryDate > 0 && block.timestamp > cert.expiryDate) {
            currentStatus = CertificateStatus.Expired;
        }

        emit CertificateVerified(_certificateId, msg.sender);

        return (cert.certType, cert.issuer, cert.holder, cert.issueDate, cert.expiryDate, currentStatus, cert.revocationReason);
    }

    // API: POST verify/{hash}
    function verifyCertificateByHash(string memory _fileHash) public onlyActiveUser onlyVerifier returns (
        string memory certificateId,
        CertificateStatus status
    ) {
        string memory certId = hashToCertId[_fileHash];
        require(bytes(certId).length != 0, "Certificate not found for this hash.");
        
        (,,,,, CertificateStatus currentStatus, ) = verifyCertificateById(certId);
        return (certId, currentStatus);
    }

    // ==========================================
    // GETTERS (For Backend Pagination & Filtering)
    // ==========================================

    // API: GET holder/certificates/{holderId}
    function getHolderCertificates(address _holder) public view returns (string[] memory) {
        return holderCertificates[_holder];
    }
    
    // API: GET certificates/GetByIssuer/{issuerId}
    function getIssuerCertificates(address _issuer) public view returns (string[] memory) {
        return issuerCertificates[_issuer];
    }

    // API Helper for GET certificates/all
    // Returns total count so backend can calculate pages, then backend fetches specific indices.
    function getTotalCertificatesCount() public view returns (uint256) {
        return allCertificateIds.length;
    }

    // Returns a specific certificate ID by its index
    function getCertificateIdByIndex(uint256 index) public view returns (string memory) {
        require(index < allCertificateIds.length, "Index out of bounds");
        return allCertificateIds[index];
    }
    
    // Auditor Dashboard Stats
    function getSystemStats() public view onlyActiveUser onlyAuditor returns (uint256 _totalIssued, uint256 _totalRevoked) {
        return (totalIssued, totalRevoked);
    }
}