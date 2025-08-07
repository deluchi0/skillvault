# Skill Vault - Smart Contract Documentation

## Overview
Skill Vault is a decentralized skill verification and bounty marketplace that creates a trustless ecosystem for validating professional skills and completing bounty tasks.

## Problem Solved
- **Skill Verification**: Decentralized validation without centralized authorities
- **Gig Economy Trust**: Verified skills for freelance marketplace
- **Payment Security**: Escrow-based bounty payments
- **Reputation Building**: On-chain professional reputation

## Key Features

### Skill Management
- Register skills with metadata and proficiency levels
- Peer validation system (minimum 3 validators)
- Endorsement tracking
- Categorized skill organization

### Bounty System
- Create bounties with skill requirements
- Submit proof of work
- Automatic expiry claims
- Refund mechanism for unclaimed bounties

### Reputation System
- Tracks skills verified, bounties completed/created
- Validation score for peer reviewers
- Total earnings tracking

## Contract Functions

### Core Functions

#### `register-skill`
- **Parameters**: name, category, level, metadata
- **Returns**: skill-id
- **Limits**: 50 skills per user, level 1-10

#### `validate-skill`
- **Parameters**: skill-id
- **Effect**: Adds validator, auto-verifies at threshold

#### `create-bounty`
- **Parameters**: title, description, reward, deadline, required-skills
- **Returns**: bounty-id
- **Requirement**: Locks reward + fee

#### `submit-to-bounty`
- **Parameters**: bounty-id, proof
- **Requirement**: Must have required verified skills

#### `select-winner`
- **Parameters**: bounty-id, winner
- **Requirement**: Must be bounty creator

#### `claim-expired-bounty`
- **Parameters**: bounty-id
- **Effect**: First submitter claims after deadline + 1440 blocks

### Read Functions
- `get-skill`: Retrieve skill details
- `get-bounty`: Retrieve bounty details
- `get-user-skills`: List user's skill IDs
- `get-user-reputation`: View reputation metrics
- `is-skill-verified`: Check verification status

## Usage Example

```clarity
;; Register a skill
(contract-call? .skill-vault register-skill 
    u"Solidity Development" 
    "programming" 
    u8 
    u"5+ years smart contract development")

;; Validate someone's skill
(contract-call? .skill-vault validate-skill u1)

;; Create a bounty
(contract-call? .skill-vault create-bounty
    u"Build DEX Interface"
    u"Create React frontend for decentralized exchange"
    u5000000  ;; 5 STX reward
    u150000   ;; deadline
    (list u1 u3 u5))  ;; required skill IDs

;; Submit to bounty
(contract-call? .skill-vault submit-to-bounty 
    u1 
    u"github.com/mywork/dex-ui")

;; Select winner
(contract-call? .skill-vault select-winner u1 'SP2J6Y09...)
```

## Fee Structure
- **Platform Fee**: 0.3% (30 basis points)
- **Maximum**: 5% (owner adjustable)
- **Collected on**: Successful bounty completions

## Security Features
1. **Self-validation prevention**
2. **Deadline enforcement**
3. **Duplicate submission checks**
4. **Balance verification**
5. **Status-based state machine**
6. **Maximum limits on arrays**

## Contract Limits
- 50 skills per user
- 20 validators per skill
- 50 submissions per bounty
- 100 bounties per user
- 5 required skills per bounty

## Deployment
1. Deploy to Stacks network
2. Set platform fee (optional)
3. Adjust min-validators (default: 3)
4. Monitor via read-only functions

## Testing Checklist
- Skill registration and validation flow
- Bounty creation with STX locking
- Submission with skill verification
- Winner selection and payment
- Expired bounty claims
- Edge cases (zero amounts, past deadlines)

## Future Enhancements
- Skill NFT minting
- Multi-stage bounties
- Skill decay over time
- Anonymous validation
- DAO governance
- Cross-chain validation
