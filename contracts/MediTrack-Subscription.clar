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
