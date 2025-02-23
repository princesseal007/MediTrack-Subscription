;; MediTrack-Subscription
;; Healthcare provider subscription management for patient records

;; Constants for subscription tiers
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TIER (err u101))
(define-constant ERR-SUBSCRIPTION-EXPIRED (err u102))

;; Subscription tiers
(define-data-var basic-tier-price uint u1000)
(define-data-var specialist-tier-price uint u2000)

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
