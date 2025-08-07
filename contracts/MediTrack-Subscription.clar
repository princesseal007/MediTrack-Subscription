;; MediTrack-Subscription
;; Healthcare provider subscription management for patient records

;; Constants for subscription tiers
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TIER (err u101))
(define-constant ERR-SUBSCRIPTION-EXPIRED (err u102))

;; Subscription tiers
(define-data-var basic-tier-price uint u1000)
(define-data-var specialist-tier-price uint u2000)
(define-constant ERR-BACKUP-NOT-FOUND (err u300))
(define-constant ERR-BACKUP-EXPIRED (err u301))
(define-constant ERR-UNAUTHORIZED-RECOVERY (err u302))
(define-constant ERR-INVALID-BACKUP-HASH (err u303))

(define-constant BACKUP-RETENTION-BLOCKS u52560)
(define-data-var backup-nonce uint u0)

(define-map subscription-backups
    {owner: principal, backup-id: uint}
    {
        data-hash: (buff 32),
        tier: (string-ascii 20),
        expiration: uint,
        emergency-access: bool,
        creation-block: uint,
        backup-expiry: uint,
        verified: bool
    }
)

(define-map backup-recovery-keys
    principal
    {
        recovery-principal: (optional principal),
        recovery-enabled: bool,
        last-updated: uint
    }
)

;; Data maps
(define-map subscriptions
    principal
    {
        tier: (string-ascii 20),
        expiration: uint,
        emergency-access: bool
    }
)

;; Public functions
(define-public (subscribe (tier (string-ascii 20)))
    (let
        ((price (if (is-eq tier "basic")
            (var-get basic-tier-price)
            (var-get specialist-tier-price))))
        
        (map-set subscriptions tx-sender
            {
                tier: tier,
                expiration: (+ stacks-block-height u8760), ;; 1 year in blocks
                emergency-access: false
            }
        )
        (ok true)
    )
)

;; Enable emergency access
(define-public (enable-emergency-access)
    (let ((current-subscription (unwrap! (map-get? subscriptions tx-sender) ERR-NOT-AUTHORIZED)))
        (map-set subscriptions tx-sender
            (merge current-subscription { emergency-access: true })
        )
        (ok true)
    )
)

;; Read only functions
(define-read-only (get-subscription (provider principal))
    (ok (map-get? subscriptions provider))
)

(define-read-only (is-active-subscriber (provider principal))
    (match (map-get? subscriptions provider)
        subscription (ok (< stacks-block-height (get expiration subscription)))
        (ok false)
    )
)



(define-public (renew-subscription)
    (let ((current-sub (unwrap! (map-get? subscriptions tx-sender) ERR-NOT-AUTHORIZED)))
        (map-set subscriptions tx-sender
            (merge current-sub 
                { expiration: (+ (get expiration current-sub) u8760) })
        )
        (ok true)
    )
)



(define-constant PREMIUM-TIER "premium")
(define-data-var premium-tier-price uint u3000)

(define-map tier-permissions
    (string-ascii 20)
    {
        can-write: bool,
        can-share: bool,
        max-patients: uint
    }
)

(define-constant REFUND-PERIOD u720) ;; 30 days in blocks
(define-constant ERR-PAST-REFUND (err u103))

(define-public (cancel-subscription)
    (let ((current-sub (unwrap! (map-get? subscriptions tx-sender) ERR-NOT-AUTHORIZED)))
        (if (< (- stacks-block-height (get expiration current-sub)) REFUND-PERIOD)
            (begin
                (map-delete subscriptions tx-sender)
                (ok true)
            )
            ERR-PAST-REFUND
        )
    )
)
(define-map paused-subscriptions
    principal
    {
        remaining-blocks: uint,
        pause-date: uint
    }
)

(define-public (pause-subscription)
    (let ((current-sub (unwrap! (map-get? subscriptions tx-sender) ERR-NOT-AUTHORIZED)))
        (map-set paused-subscriptions tx-sender
            {
                remaining-blocks: (- (get expiration current-sub) stacks-block-height),
                pause-date: stacks-block-height
            }
        )
        (ok true)
    )
)


(define-constant MIN-GROUP-SIZE u5)
(define-constant GROUP-DISCOUNT-PERCENT u10)

(define-map group-subscriptions
    principal
    {
        members: (list 20 principal),
        discount: uint
    }
)

(define-public (create-group-subscription (members (list 20 principal)))
    (if (>= (len members) MIN-GROUP-SIZE)
        (begin
            (map-set group-subscriptions tx-sender
                {
                    members: members,
                    discount: GROUP-DISCOUNT-PERCENT
                }
            )
            (ok true)
        )
        (err u104)
    )
)



(define-map subscription-analytics
    principal
    {
        access-count: uint,
        last-access: uint,
        total-patients: uint
    }
)

(define-public (log-subscription-usage)
    (let ((current-analytics (default-to 
            { access-count: u0, last-access: u0, total-patients: u0 }
            (map-get? subscription-analytics tx-sender))))
        (map-set subscription-analytics tx-sender
            (merge current-analytics 
                { 
                    access-count: (+ (get access-count current-analytics) u1),
                    last-access: stacks-block-height
                }
            )
        )
        (ok true)
    )
)



(define-map emergency-contacts
    principal
    {
        contact: principal,
        relationship: (string-ascii 20),
        can-access: bool
    }
)

(define-public (add-emergency-contact (contact principal) (relationship (string-ascii 20)))
    (ok (map-set emergency-contacts tx-sender
        {
            contact: contact,
            relationship: relationship,
            can-access: true
        }))
)


(define-constant ERR-INVALID-UPGRADE (err u105))

(define-read-only (is-valid-tier (tier (string-ascii 20)))
    (or
        (is-eq tier "basic")
        (is-eq tier "specialist")
        (is-eq tier PREMIUM-TIER)
    )
)

(define-public (change-subscription-tier (new-tier (string-ascii 20)))
    (let (
        (current-sub (unwrap! (map-get? subscriptions tx-sender) ERR-NOT-AUTHORIZED))
        (current-block stacks-block-height)
    )
        (if (is-valid-tier new-tier)
            (begin
                (map-set subscriptions tx-sender
                    (merge current-sub { tier: new-tier })
                )
                (ok true)
            )
            ERR-INVALID-TIER
        )
    )
)


(define-map usage-tiers
    principal
    {monthly-access: uint, tier-multiplier: uint})

(define-constant TIER1-THRESHOLD u100)
(define-constant TIER2-THRESHOLD u500)

(define-public (calculate-usage-tier)
    (let ((usage (default-to 
        {access-count: u0, last-access: u0, total-patients: u0}
        (map-get? subscription-analytics tx-sender))))
        (map-set usage-tiers tx-sender
            {
                monthly-access: (get access-count usage),
                tier-multiplier: (if (> (get access-count usage) TIER2-THRESHOLD)
                    u2
                    (if (> (get access-count usage) TIER1-THRESHOLD)
                        u15
                        u1))
            }
        )
        (ok true)
    )
)


(define-map auto-renewal
    principal
    {enabled: bool, last-renewal: uint})

(define-public (toggle-auto-renewal)
    (let ((current-status (default-to 
        {enabled: false, last-renewal: u0}
        (map-get? auto-renewal tx-sender))))
        (map-set auto-renewal tx-sender
            {
                enabled: (not (get enabled current-status)),
                last-renewal: stacks-block-height
            }
        )
        (ok true)
    )
)


(define-constant ERR-TRANSFER-FAILED (err u106))

(define-public (transfer-subscription (new-owner principal))
    (let ((current-sub (unwrap! (map-get? subscriptions tx-sender) ERR-NOT-AUTHORIZED)))
        (begin
            (map-delete subscriptions tx-sender)
            (map-set subscriptions new-owner current-sub)
            (ok true)
        )
    )
)



(define-map subscription-bundles
    (string-ascii 20)
    {
        name: (string-ascii 20),
        duration: uint,
        discount: uint,
        features: (list 5 (string-ascii 20))
    }
)

(define-public (create-bundle-subscription (bundle-name (string-ascii 20)))
    (let ((bundle (unwrap! (map-get? subscription-bundles bundle-name) ERR-INVALID-TIER)))
        (map-set subscriptions tx-sender
            {
                tier: (get name bundle),
                expiration: (+ stacks-block-height (get duration bundle)),
                emergency-access: false
            }
        )
        (ok true)
    )
)


(define-map loyalty-points
    principal
    {
        points: uint,
        level: (string-ascii 10),
        rewards-claimed: uint
    }
)

(define-public (accumulate-points)
    (let ((current-points (default-to 
        {points: u0, level: "bronze", rewards-claimed: u0}
        (map-get? loyalty-points tx-sender))))
        (map-set loyalty-points tx-sender
            (merge current-points 
                {points: (+ (get points current-points) u10)}
            )
        )
        (ok true)
    )
)


(define-map seasonal-promotions
    uint
    {
        name: (string-ascii 20),
        discount: uint,
        start-block: uint,
        end-block: uint
    }
)

(define-public (apply-seasonal-promotion (promotion-id uint))
    (let ((promotion (unwrap! (map-get? seasonal-promotions promotion-id) ERR-INVALID-TIER)))
        (if (and 
            (>= stacks-block-height (get start-block promotion))
            (<= stacks-block-height (get end-block promotion)))
            (ok true)
            (err u107)
        )
    )
)


(define-map usage-reports
    principal
    {
        daily-accesses: uint,
        peak-usage-time: uint,
        feature-usage: (list 5 (string-ascii 20))
    }
)

(define-public (generate-usage-report)
    (let ((current-usage (default-to 
        {daily-accesses: u0, peak-usage-time: u0, feature-usage: (list)}
        (map-get? usage-reports tx-sender))))
        (map-set usage-reports tx-sender
            (merge current-usage 
                {
                    daily-accesses: (+ (get daily-accesses current-usage) u1),
                    peak-usage-time: stacks-block-height
                }
            )
        )
        (ok true)
    )
)


(define-map referral-system
    principal
    {
        referrer: (optional principal),
        referral-count: uint,
        rewards-earned: uint
    }
)

(define-constant REFERRAL-REWARD u100)
(define-constant MAX-REFERRAL-REWARD u1000)

(define-public (register-referral (referrer principal))
    (let ((current-stats (default-to 
            {referrer: none, referral-count: u0, rewards-earned: u0}
            (map-get? referral-system referrer))))
        (begin
            (map-set referral-system tx-sender
                {
                    referrer: (some referrer),
                    referral-count: u0,
                    rewards-earned: u0
                }
            )
            (map-set referral-system referrer
                (merge current-stats 
                    {
                        referral-count: (+ (get referral-count current-stats) u1),
                        rewards-earned: (+ (get rewards-earned current-stats) REFERRAL-REWARD)
                    }
                )
            )
            (ok true)
        )
    )
)
(define-public (claim-referral-reward)
    (let ((current-stats (unwrap! (map-get? referral-system tx-sender) ERR-NOT-AUTHORIZED)))
        (if (< (get rewards-earned current-stats) MAX-REFERRAL-REWARD)
            (begin
                (map-set referral-system tx-sender
                    (merge current-stats 
                        { rewards-earned: (+ (get rewards-earned current-stats) REFERRAL-REWARD) }
                    )
                )
                (ok true)
            )
            ERR-INVALID-TIER
        )
    )
)

(define-map subscription-metrics
    principal
    {
        total-sessions: uint,
        average-session-length: uint,
        peak-usage-blocks: (list 10 uint),
        feature-usage-count: {
            records-accessed: uint,
            emergency-calls: uint,
            data-exports: uint
        }
    }
)

(define-public (record-session-metrics (session-length uint) (feature-type (string-ascii 20)))
    (let ((current-metrics (default-to 
            {
                total-sessions: u0,
                average-session-length: u0,
                peak-usage-blocks: (list),
                feature-usage-count: {
                    records-accessed: u0,
                    emergency-calls: u0,
                    data-exports: u0
                }
            }
            (map-get? subscription-metrics tx-sender))))
        (map-set subscription-metrics tx-sender
            (merge current-metrics 
                {
                    total-sessions: (+ (get total-sessions current-metrics) u1),
                    average-session-length: (/ (+ 
                        (* (get average-session-length current-metrics) (get total-sessions current-metrics))
                        session-length
                    ) (+ (get total-sessions current-metrics) u1)),
                    peak-usage-blocks: (unwrap-panic (as-max-len? 
                        (append (get peak-usage-blocks current-metrics) stacks-block-height)
                        u10
                    ))
                }
            )
        )
        (ok true)
    )
)


(define-constant ERR-NOT-OWNER (err u200))
(define-constant ERR-ALREADY-SIGNED (err u201))
(define-constant ERR-INSUFFICIENT-SIGNATURES (err u202))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u203))
(define-constant ERR-PROPOSAL-EXPIRED (err u204))
(define-constant ERR-INVALID-SIGNER (err u205))

(define-data-var proposal-nonce uint u0)

(define-map multisig-wallets
    principal
    {
        signers: (list 10 principal),
        required-signatures: uint,
        subscription-tier: (string-ascii 20),
        is-active: bool
    }
)

(define-map subscription-proposals
    uint
    {
        wallet: principal,
        action: (string-ascii 20),
        new-tier: (optional (string-ascii 20)),
        signatures: (list 10 principal),
        expiration: uint,
        executed: bool
    }
)

(define-map signer-permissions
    {wallet: principal, signer: principal}
    {can-propose: bool, can-sign: bool}
)



(define-private (setup-signer-permissions (signer principal) (wallet principal))
    (begin
        (map-set signer-permissions {wallet: wallet, signer: signer}
            {can-propose: true, can-sign: true}
        )
        wallet
    )
)

(define-public (propose-subscription-action (wallet principal) (action (string-ascii 20)) (new-tier (optional (string-ascii 20))))
    (let (
        (wallet-info (unwrap! (map-get? multisig-wallets wallet) ERR-NOT-OWNER))
        (proposal-id (var-get proposal-nonce))
        (signer-perms (unwrap! (map-get? signer-permissions {wallet: wallet, signer: tx-sender}) ERR-INVALID-SIGNER))
    )
        (asserts! (get can-propose signer-perms) ERR-INVALID-SIGNER)
        (map-set subscription-proposals proposal-id
            {
                wallet: wallet,
                action: action,
                new-tier: new-tier,
                signatures: (list tx-sender),
                expiration: (+ stacks-block-height u1440),
                executed: false
            }
        )
        (var-set proposal-nonce (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (sign-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? subscription-proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
        (wallet-info (unwrap! (map-get? multisig-wallets (get wallet proposal)) ERR-NOT-OWNER))
        (signer-perms (unwrap! (map-get? signer-permissions {wallet: (get wallet proposal), signer: tx-sender}) ERR-INVALID-SIGNER))
    )
        (asserts! (get can-sign signer-perms) ERR-INVALID-SIGNER)
        (asserts! (< stacks-block-height (get expiration proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (is-none (index-of (get signatures proposal) tx-sender)) ERR-ALREADY-SIGNED)
        
        (map-set subscription-proposals proposal-id
            (merge proposal 
                {signatures: (unwrap-panic (as-max-len? (append (get signatures proposal) tx-sender) u10))}
            )
        )
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? subscription-proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
        (wallet-info (unwrap! (map-get? multisig-wallets (get wallet proposal)) ERR-NOT-OWNER))
        (signature-count (len (get signatures proposal)))
    )
        (asserts! (>= signature-count (get required-signatures wallet-info)) ERR-INSUFFICIENT-SIGNATURES)
        (asserts! (< stacks-block-height (get expiration proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXPIRED)
        
        (map-set subscription-proposals proposal-id
            (merge proposal {executed: true})
        )
        
        (if (is-eq (get action proposal) "change-tier")
            (execute-tier-change (get wallet proposal) (unwrap-panic (get new-tier proposal)))
            (if (is-eq (get action proposal) "cancel")
                (execute-cancellation (get wallet proposal))
                (if (is-eq (get action proposal) "renew")
                    (execute-renewal (get wallet proposal))
                    (ok true)
                )
            )
        )
    )
)


(define-public (create-subscription-backup (data-hash (buff 32)))
    (let (
        (current-sub (unwrap! (map-get? subscriptions tx-sender) ERR-NOT-AUTHORIZED))
        (backup-id (var-get backup-nonce))
    )
        (map-set subscription-backups {owner: tx-sender, backup-id: backup-id}
            {
                data-hash: data-hash,
                tier: (get tier current-sub),
                expiration: (get expiration current-sub),
                emergency-access: (get emergency-access current-sub),
                creation-block: stacks-block-height,
                backup-expiry: (+ stacks-block-height BACKUP-RETENTION-BLOCKS),
                verified: true
            }
        )
        (var-set backup-nonce (+ backup-id u1))
        (ok backup-id)
    )
)

(define-public (restore-from-backup (backup-id uint) (data-hash (buff 32)))
    (let (
        (backup (unwrap! (map-get? subscription-backups {owner: tx-sender, backup-id: backup-id}) ERR-BACKUP-NOT-FOUND))
        (recovery-info (map-get? backup-recovery-keys tx-sender))
    )
        (asserts! (< stacks-block-height (get backup-expiry backup)) ERR-BACKUP-EXPIRED)
        (asserts! (is-eq (get data-hash backup) data-hash) ERR-INVALID-BACKUP-HASH)
        (asserts! (get verified backup) ERR-INVALID-BACKUP-HASH)
        
        (map-set subscriptions tx-sender
            {
                tier: (get tier backup),
                expiration: (get expiration backup),
                emergency-access: (get emergency-access backup)
            }
        )
        (ok true)
    )
)

(define-public (setup-recovery-delegate (recovery-principal principal))
    (ok (map-set backup-recovery-keys tx-sender
        {
            recovery-principal: (some recovery-principal),
            recovery-enabled: true,
            last-updated: stacks-block-height
        }))
)

(define-public (delegate-recovery (original-owner principal) (backup-id uint) (data-hash (buff 32)))
    (let (
        (recovery-info (unwrap! (map-get? backup-recovery-keys original-owner) ERR-UNAUTHORIZED-RECOVERY))
        (backup (unwrap! (map-get? subscription-backups {owner: original-owner, backup-id: backup-id}) ERR-BACKUP-NOT-FOUND))
    )
        (asserts! (get recovery-enabled recovery-info) ERR-UNAUTHORIZED-RECOVERY)
        (asserts! (is-eq (some tx-sender) (get recovery-principal recovery-info)) ERR-UNAUTHORIZED-RECOVERY)
        (asserts! (< stacks-block-height (get backup-expiry backup)) ERR-BACKUP-EXPIRED)
        (asserts! (is-eq (get data-hash backup) data-hash) ERR-INVALID-BACKUP-HASH)
        
        (map-set subscriptions original-owner
            {
                tier: (get tier backup),
                expiration: (get expiration backup),
                emergency-access: (get emergency-access backup)
            }
        )
        (ok true)
    )
)

(define-public (cleanup-expired-backups (backup-ids (list 20 uint)))
    (ok (fold cleanup-single-backup backup-ids true))
)

(define-private (cleanup-single-backup (backup-id uint) (success bool))
    (match (map-get? subscription-backups {owner: tx-sender, backup-id: backup-id})
        backup (if (>= stacks-block-height (get backup-expiry backup))
            (begin
                (map-delete subscription-backups {owner: tx-sender, backup-id: backup-id})
                success
            )
            success
        )
        success
    )
)

(define-read-only (get-backup-info (owner principal) (backup-id uint))
    (ok (map-get? subscription-backups {owner: owner, backup-id: backup-id}))
)

(define-read-only (verify-backup-integrity (owner principal) (backup-id uint) (expected-hash (buff 32)))
    (match (map-get? subscription-backups {owner: owner, backup-id: backup-id})
        backup (ok (and 
            (is-eq (get data-hash backup) expected-hash)
            (< stacks-block-height (get backup-expiry backup))
            (get verified backup)
        ))
        (ok false)
    )
)

(define-read-only (get-recovery-delegate (owner principal))
    (ok (map-get? backup-recovery-keys owner))
)

(define-private (execute-tier-change (wallet principal) (new-tier (string-ascii 20)))
    (let ((wallet-info (unwrap-panic (map-get? multisig-wallets wallet))))
        (map-set multisig-wallets wallet
            (merge wallet-info {subscription-tier: new-tier})
        )
        (ok true)
    )
)

(define-private (execute-cancellation (wallet principal))
    (let ((wallet-info (unwrap-panic (map-get? multisig-wallets wallet))))
        (map-set multisig-wallets wallet
            (merge wallet-info {is-active: false})
        )
        (ok true)
    )
)

(define-private (execute-renewal (wallet principal))
    (let ((wallet-info (unwrap-panic (map-get? multisig-wallets wallet))))
        (map-set multisig-wallets wallet
            (merge wallet-info {is-active: true})
        )
        (ok true)
    )
)

(define-public (add-signer (wallet principal) (new-signer principal))
    (let (
        (wallet-info (unwrap! (map-get? multisig-wallets wallet) ERR-NOT-OWNER))
        (current-signers (get signers wallet-info))
    )
        (asserts! (is-some (index-of current-signers tx-sender)) ERR-INVALID-SIGNER)
        (map-set multisig-wallets wallet
            (merge wallet-info 
                {signers: (unwrap-panic (as-max-len? (append current-signers new-signer) u10))}
            )
        )
        (map-set signer-permissions {wallet: wallet, signer: new-signer}
            {can-propose: true, can-sign: true}
        )
        (ok true)
    )
)


(define-read-only (get-multisig-wallet (wallet principal))
    (ok (map-get? multisig-wallets wallet))
)

(define-read-only (get-proposal (proposal-id uint))
    (ok (map-get? subscription-proposals proposal-id))
)

(define-read-only (get-proposal-signature-count (proposal-id uint))
    (match (map-get? subscription-proposals proposal-id)
        proposal (ok (len (get signatures proposal)))
        (ok u0)
    )
)

(define-read-only (is-signer (wallet principal) (signer principal))
    (match (map-get? multisig-wallets wallet)
        wallet-info (ok (is-some (index-of (get signers wallet-info) signer)))
        (ok false)
    )
)

(define-read-only (can-execute-proposal (proposal-id uint))
    (match (map-get? subscription-proposals proposal-id)
        proposal (match (map-get? multisig-wallets (get wallet proposal))
            wallet-info (ok (and
                (>= (len (get signatures proposal)) (get required-signatures wallet-info))
                (< stacks-block-height (get expiration proposal))
                (not (get executed proposal))
            ))
            (ok false)
        )
        (ok false)
    )
)