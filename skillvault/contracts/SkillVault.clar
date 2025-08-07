;; Skill Vault - Decentralized Skill Verification & Bounty Marketplace

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-invalid-skill (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-not-found (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-invalid-status (err u105))
(define-constant err-deadline-passed (err u106))
(define-constant err-invalid-amount (err u107))
(define-constant err-max-validators (err u108))
(define-constant err-already-validated (err u109))
(define-constant err-self-validation (err u110))
(define-constant err-invalid-submission (err u111))
(define-constant err-already-claimed (err u112))

;; Data Variables
(define-data-var skill-counter uint u0)
(define-data-var bounty-counter uint u0)
(define-data-var platform-fee uint u30) ;; 0.3% = 30 basis points
(define-data-var min-validators uint u3)
(define-data-var total-fees uint u0)

;; Data Maps
(define-map skills 
    uint
    {
        owner: principal,
        name: (string-utf8 50),
        category: (string-ascii 30),
        level: uint,
        validators: (list 20 principal),
        validation-count: uint,
        verified: bool,
        metadata: (string-utf8 256),
        created-at: uint
    }
)

(define-map bounties
    uint
    {
        creator: principal,
        title: (string-utf8 100),
        description: (string-utf8 500),
        reward: uint,
        required-skills: (list 5 uint),
        deadline: uint,
        status: (string-ascii 20),
        winner: (optional principal),
        submissions: (list 50 {applicant: principal, proof: (string-utf8 256), timestamp: uint})
    }
)

(define-map user-skills principal (list 50 uint))
(define-map user-bounties principal (list 100 uint))
(define-map skill-validators principal (list 100 uint))
(define-map user-reputation 
    principal 
    {
        skills-verified: uint,
        bounties-completed: uint,
        bounties-created: uint,
        validation-score: uint,
        total-earned: uint
    }
)

(define-map skill-endorsements 
    {skill-id: uint, validator: principal} 
    {endorsed: bool, timestamp: uint}
)

;; Private Functions
(define-private (calculate-fee (amount uint))
    (/ (* amount (var-get platform-fee)) u10000)
)

(define-private (has-required-skills (user principal) (skill-ids (list 5 uint)))
    (let ((user-skill-list (default-to (list) (map-get? user-skills user))))
        (fold check-skill skill-ids true)
    )
)

(define-private (check-skill (skill-id uint) (prev bool))
    (and prev 
        (match (map-get? skills skill-id)
            skill (and (get verified skill) 
                      (is-eq (get owner skill) tx-sender))
            false
        )
    )
)

(define-private (update-reputation (user principal) (field (string-ascii 20)) (amount uint))
    (let ((current-rep (default-to 
            {skills-verified: u0, bounties-completed: u0, bounties-created: u0, 
             validation-score: u0, total-earned: u0}
            (map-get? user-reputation user))))
        (if (is-eq field "skills-verified")
            (map-set user-reputation user 
                (merge current-rep {skills-verified: (+ (get skills-verified current-rep) amount)}))
        (if (is-eq field "bounties-completed")
            (map-set user-reputation user 
                (merge current-rep {bounties-completed: (+ (get bounties-completed current-rep) amount)}))
        (if (is-eq field "bounties-created")
            (map-set user-reputation user 
                (merge current-rep {bounties-created: (+ (get bounties-created current-rep) amount)}))
        (if (is-eq field "validation-score")
            (map-set user-reputation user 
                (merge current-rep {validation-score: (+ (get validation-score current-rep) amount)}))
        (if (is-eq field "total-earned")
            (map-set user-reputation user 
                (merge current-rep {total-earned: (+ (get total-earned current-rep) amount)}))
            false
        )))))
    )
)

;; Public Functions
(define-public (register-skill (name (string-utf8 50)) (category (string-ascii 30)) 
                               (level uint) (metadata (string-utf8 256)))
    (let ((skill-id (+ (var-get skill-counter) u1))
          (current-skills (default-to (list) (map-get? user-skills tx-sender))))
        (asserts! (<= level u10) err-invalid-skill)
        (asserts! (< (len current-skills) u50) err-invalid-skill)
        
        (map-set skills skill-id {
            owner: tx-sender,
            name: name,
            category: category,
            level: level,
            validators: (list),
            validation-count: u0,
            verified: false,
            metadata: metadata,
            created-at: stacks-block-height
        })
        
        (map-set user-skills tx-sender 
            (unwrap! (as-max-len? (append current-skills skill-id) u50) err-invalid-skill))
        
        (var-set skill-counter skill-id)
        (ok skill-id)
    )
)

(define-public (validate-skill (skill-id uint))
    (let ((skill (unwrap! (map-get? skills skill-id) err-not-found))
          (current-validators (get validators skill)))
        (asserts! (not (is-eq (get owner skill) tx-sender)) err-self-validation)
        (asserts! (is-none (index-of current-validators tx-sender)) err-already-validated)
        (asserts! (< (len current-validators) u20) err-max-validators)
        
        (let ((new-validators (unwrap! (as-max-len? (append current-validators tx-sender) u20) 
                                       err-max-validators))
              (new-count (+ (get validation-count skill) u1))
              (validator-skills (default-to (list) (map-get? skill-validators tx-sender))))
            
            (map-set skills skill-id 
                (merge skill {
                    validators: new-validators,
                    validation-count: new-count,
                    verified: (>= new-count (var-get min-validators))
                }))
            
            (map-set skill-endorsements {skill-id: skill-id, validator: tx-sender}
                {endorsed: true, timestamp: stacks-block-height})
            
            (map-set skill-validators tx-sender 
                (unwrap! (as-max-len? (append validator-skills skill-id) u100) err-invalid-skill))
            
            (update-reputation tx-sender "validation-score" u1)
            
            (if (>= new-count (var-get min-validators))
                (update-reputation (get owner skill) "skills-verified" u1)
                false
            )
            
            (ok true)
        )
    )
)

(define-public (create-bounty (title (string-utf8 100)) (description (string-utf8 500))
                             (reward uint) (deadline uint) (required-skills (list 5 uint)))
    (let ((bounty-id (+ (var-get bounty-counter) u1))
          (fee (calculate-fee reward))
          (total-amount (+ reward fee)))
        (asserts! (> reward u0) err-invalid-amount)
        (asserts! (> deadline stacks-block-height) err-deadline-passed)
        (asserts! (>= (stx-get-balance tx-sender) total-amount) err-insufficient-funds)
        
        (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
        
        (map-set bounties bounty-id {
            creator: tx-sender,
            title: title,
            description: description,
            reward: reward,
            required-skills: required-skills,
            deadline: deadline,
            status: "open",
            winner: none,
            submissions: (list)
        })
        
        (let ((user-bounty-list (default-to (list) (map-get? user-bounties tx-sender))))
            (map-set user-bounties tx-sender 
                (unwrap! (as-max-len? (append user-bounty-list bounty-id) u100) err-invalid-submission))
        )
        
        (var-set bounty-counter bounty-id)
        (update-reputation tx-sender "bounties-created" u1)
        (ok bounty-id)
    )
)

(define-public (submit-to-bounty (bounty-id uint) (proof (string-utf8 256)))
    (let ((bounty (unwrap! (map-get? bounties bounty-id) err-not-found)))
        (asserts! (is-eq (get status bounty) "open") err-invalid-status)
        (asserts! (< stacks-block-height (get deadline bounty)) err-deadline-passed)
        (asserts! (has-required-skills tx-sender (get required-skills bounty)) err-invalid-skill)
        
        (let ((current-submissions (get submissions bounty))
              (new-submission {applicant: tx-sender, proof: proof, timestamp: stacks-block-height}))
            (asserts! (is-none (index-of (map get-applicant current-submissions) tx-sender)) 
                     err-already-exists)
            
            (map-set bounties bounty-id
                (merge bounty {
                    submissions: (unwrap! (as-max-len? (append current-submissions new-submission) u50) 
                                        err-invalid-submission)
                }))
            
            (ok true)
        )
    )
)

(define-private (get-applicant (submission {applicant: principal, proof: (string-utf8 256), timestamp: uint}))
    (get applicant submission)
)

(define-public (select-winner (bounty-id uint) (winner principal))
    (let ((bounty (unwrap! (map-get? bounties bounty-id) err-not-found)))
        (asserts! (is-eq (get creator bounty) tx-sender) err-unauthorized)
        (asserts! (is-eq (get status bounty) "open") err-invalid-status)
        
        (let ((submissions (get submissions bounty)))
            (asserts! (is-some (index-of (map get-applicant submissions) winner)) err-not-found)
            
            (try! (as-contract (stx-transfer? (get reward bounty) tx-sender winner)))
            (try! (as-contract (stx-transfer? (calculate-fee (get reward bounty)) tx-sender contract-owner)))
            
            (var-set total-fees (+ (var-get total-fees) (calculate-fee (get reward bounty))))
            
            (map-set bounties bounty-id
                (merge bounty {
                    status: "completed",
                    winner: (some winner)
                }))
            
            (update-reputation winner "bounties-completed" u1)
            (update-reputation winner "total-earned" (get reward bounty))
            
            (ok true)
        )
    )
)

(define-public (cancel-bounty (bounty-id uint))
    (let ((bounty (unwrap! (map-get? bounties bounty-id) err-not-found)))
        (asserts! (is-eq (get creator bounty) tx-sender) err-unauthorized)
        (asserts! (is-eq (get status bounty) "open") err-invalid-status)
        (asserts! (is-eq (len (get submissions bounty)) u0) err-invalid-status)
        
        (try! (as-contract (stx-transfer? (+ (get reward bounty) (calculate-fee (get reward bounty))) 
                                         tx-sender (get creator bounty))))
        
        (map-set bounties bounty-id
            (merge bounty {status: "cancelled"}))
        
        (ok true)
    )
)

(define-public (claim-expired-bounty (bounty-id uint))
    (let ((bounty (unwrap! (map-get? bounties bounty-id) err-not-found)))
        (asserts! (> stacks-block-height (+ (get deadline bounty) u1440)) err-deadline-passed)
        (asserts! (is-eq (get status bounty) "open") err-invalid-status)
        (asserts! (> (len (get submissions bounty)) u0) err-invalid-submission)
        
        (let ((submissions (get submissions bounty))
              (first-submission (unwrap! (element-at submissions u0) err-not-found)))
            (asserts! (is-eq (get applicant first-submission) tx-sender) err-unauthorized)
            
            (try! (as-contract (stx-transfer? (get reward bounty) tx-sender tx-sender)))
            (try! (as-contract (stx-transfer? (calculate-fee (get reward bounty)) tx-sender contract-owner)))
            
            (var-set total-fees (+ (var-get total-fees) (calculate-fee (get reward bounty))))
            
            (map-set bounties bounty-id
                (merge bounty {
                    status: "expired-claimed",
                    winner: (some tx-sender)
                }))
            
            (update-reputation tx-sender "bounties-completed" u1)
            (update-reputation tx-sender "total-earned" (get reward bounty))
            
            (ok true)
        )
    )
)

(define-public (update-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= new-fee u500) err-invalid-amount)
        (var-set platform-fee new-fee)
        (ok true)
    )
)

(define-public (update-min-validators (new-min uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (and (>= new-min u1) (<= new-min u10)) err-invalid-amount)
        (var-set min-validators new-min)
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-skill (skill-id uint))
    (map-get? skills skill-id)
)

(define-read-only (get-bounty (bounty-id uint))
    (map-get? bounties bounty-id)
)

(define-read-only (get-user-skills (user principal))
    (default-to (list) (map-get? user-skills user))
)

(define-read-only (get-user-bounties (user principal))
    (default-to (list) (map-get? user-bounties user))
)

(define-read-only (get-user-reputation (user principal))
    (default-to {skills-verified: u0, bounties-completed: u0, bounties-created: u0, 
                validation-score: u0, total-earned: u0}
        (map-get? user-reputation user))
)

(define-read-only (get-skill-endorsement (skill-id uint) (validator principal))
    (map-get? skill-endorsements {skill-id: skill-id, validator: validator})
)

(define-read-only (is-skill-verified (skill-id uint))
    (match (map-get? skills skill-id)
        skill (get verified skill)
        false
    )
)

(define-read-only (get-platform-stats)
    {
        total-skills: (var-get skill-counter),
        total-bounties: (var-get bounty-counter),
        platform-fee: (var-get platform-fee),
        min-validators: (var-get min-validators),
        total-fees-collected: (var-get total-fees)
    }
)