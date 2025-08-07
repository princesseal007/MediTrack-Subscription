;; Healthcare Compliance Auditing System
;; Tracks data access events and maintains HIPAA compliance audit trails

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-ACCESS-TYPE (err u401))
(define-constant ERR-AUDIT-NOT-FOUND (err u402))
(define-constant ERR-VIOLATION-EXISTS (err u403))
(define-constant ERR-INSUFFICIENT-TIER (err u404))
(define-constant ERR-INVALID-SEVERITY (err u405))

;; Audit event types
(define-constant ACCESS-TYPE-READ "read")
(define-constant ACCESS-TYPE-WRITE "write")
(define-constant ACCESS-TYPE-DELETE "delete")
(define-constant ACCESS-TYPE-EXPORT "export")
(define-constant ACCESS-TYPE-EMERGENCY "emergency")

;; Violation severity levels
(define-constant SEVERITY-LOW "low")
(define-constant SEVERITY-MEDIUM "medium")
(define-constant SEVERITY-HIGH "high")
(define-constant SEVERITY-CRITICAL "critical")

;; Data variables
(define-data-var audit-event-counter uint u0)
(define-data-var violation-counter uint u0)
(define-data-var audit-retention-blocks uint u262800) ;; ~1 year retention

;; Audit event structure
(define-map audit-events
    uint
    {
        provider: principal,
        patient-id: (string-ascii 50),
        access-type: (string-ascii 20),
        resource-accessed: (string-ascii 100),
        timestamp: uint,
        ip-address: (string-ascii 45),
        user-agent: (string-ascii 200),
        access-duration: uint,
        data-exported: bool,
        emergency-override: bool
    }
)

;; Compliance violation tracking
(define-map compliance-violations
    uint
    {
        provider: principal,
        violation-type: (string-ascii 50),
        severity: (string-ascii 10),
        description: (string-ascii 500),
        detected-at: uint,
        audit-event-id: uint,
        resolved: bool,
        resolution-notes: (optional (string-ascii 300))
    }
)

;; Provider audit summaries
(define-map provider-audit-summary
    principal
    {
        total-access-events: uint,
        last-audit-date: uint,
        violation-count: uint,
        compliance-score: uint,
        high-risk-flags: uint,
        audit-period-start: uint
    }
)

;; Access pattern analysis for anomaly detection
(define-map access-patterns
    {provider: principal, date-block: uint}
    {
        read-count: uint,
        write-count: uint,
        delete-count: uint,
        export-count: uint,
        emergency-count: uint,
        peak-hour-access: uint,
        unusual-location-access: uint
    }
)

;; Audit configuration per provider
(define-map audit-config
    principal
    {
        audit-enabled: bool,
        real-time-monitoring: bool,
        violation-alerts: bool,
        retention-period: uint,
        compliance-level: (string-ascii 20)
    }
)

;; Public functions

;; Log a healthcare data access event
(define-public (log-access-event 
    (patient-id (string-ascii 50))
    (access-type (string-ascii 20))
    (resource-accessed (string-ascii 100))
    (ip-address (string-ascii 45))
    (user-agent (string-ascii 200))
    (access-duration uint)
    (data-exported bool)
    (emergency-override bool))
    
    (let 
        (
            (event-id (+ (var-get audit-event-counter) u1))
            (current-block stacks-block-height)
        )
        
        ;; Validate access type
        (asserts! (is-valid-access-type access-type) ERR-INVALID-ACCESS-TYPE)
        
        ;; Store audit event
        (map-set audit-events event-id
            {
                provider: tx-sender,
                patient-id: patient-id,
                access-type: access-type,
                resource-accessed: resource-accessed,
                timestamp: current-block,
                ip-address: ip-address,
                user-agent: user-agent,
                access-duration: access-duration,
                data-exported: data-exported,
                emergency-override: emergency-override
            }
        )
        
        ;; Update counter
        (var-set audit-event-counter event-id)
        
        ;; Update access patterns for anomaly detection
        (update-access-patterns access-type current-block)
        
        ;; Update provider audit summary
        (update-provider-summary)
        
        ;; Check for potential violations and ignore result
        (begin
            (unwrap-panic (check-compliance-violations event-id access-type data-exported emergency-override))
            (ok event-id)
        )
    )
)

;; Report a compliance violation
(define-public (report-violation 
    (violation-type (string-ascii 50))
    (severity (string-ascii 10))
    (description (string-ascii 500))
    (audit-event-id uint))
    
    (let 
        (
            (violation-id (+ (var-get violation-counter) u1))
        )
        
        ;; Validate severity level
        (asserts! (is-valid-severity severity) ERR-INVALID-SEVERITY)
        
        ;; Check if audit event exists
        (asserts! (is-some (map-get? audit-events audit-event-id)) ERR-AUDIT-NOT-FOUND)
        
        ;; Store violation
        (map-set compliance-violations violation-id
            {
                provider: tx-sender,
                violation-type: violation-type,
                severity: severity,
                description: description,
                detected-at: stacks-block-height,
                audit-event-id: audit-event-id,
                resolved: false,
                resolution-notes: none
            }
        )
        
        ;; Update counter
        (var-set violation-counter violation-id)
        
        ;; Update provider summary with violation
        (update-violation-count)
        
        (ok violation-id)
    )
)

;; Resolve a compliance violation
(define-public (resolve-violation 
    (violation-id uint)
    (resolution-notes (string-ascii 300)))
    
    (let 
        (
            (violation (unwrap! (map-get? compliance-violations violation-id) ERR-AUDIT-NOT-FOUND))
        )
        
        ;; Verify the provider owns this violation
        (asserts! (is-eq (get provider violation) tx-sender) ERR-NOT-AUTHORIZED)
        
        ;; Update violation status
        (map-set compliance-violations violation-id
            (merge violation 
                {
                    resolved: true,
                    resolution-notes: (some resolution-notes)
                }
            )
        )
        
        (ok true)
    )
)

;; Generate audit report for a time period
(define-public (generate-audit-report 
    (start-block uint)
    (end-block uint))
    
    (let 
        (
            (provider-summary (default-to 
                {
                    total-access-events: u0,
                    last-audit-date: u0,
                    violation-count: u0,
                    compliance-score: u100,
                    high-risk-flags: u0,
                    audit-period-start: start-block
                }
                (map-get? provider-audit-summary tx-sender)
            ))
        )
        
        ;; Update last audit date
        (map-set provider-audit-summary tx-sender
            (merge provider-summary 
                {
                    last-audit-date: stacks-block-height
                }
            )
        )
        
        (ok provider-summary)
    )
)

;; Configure audit settings for provider
(define-public (configure-audit-settings 
    (audit-enabled bool)
    (real-time-monitoring bool)
    (violation-alerts bool)
    (compliance-level (string-ascii 20)))
    
    (ok (map-set audit-config tx-sender
        {
            audit-enabled: audit-enabled,
            real-time-monitoring: real-time-monitoring,
            violation-alerts: violation-alerts,
            retention-period: (var-get audit-retention-blocks),
            compliance-level: compliance-level
        }))
)

;; Cleanup old audit records beyond retention period
(define-public (cleanup-old-audits)
    (let 
        (
            (retention-cutoff (- stacks-block-height (var-get audit-retention-blocks)))
        )
        
        ;; Note: In a real implementation, you'd iterate through old records
        ;; For simplicity, we'll just update the provider summary
        (map-set provider-audit-summary tx-sender
            (merge (default-to 
                {
                    total-access-events: u0,
                    last-audit-date: u0,
                    violation-count: u0,
                    compliance-score: u100,
                    high-risk-flags: u0,
                    audit-period-start: retention-cutoff
                }
                (map-get? provider-audit-summary tx-sender)
            ) 
            {
                audit-period-start: retention-cutoff
            })
        )
        
        (ok true)
    )
)

;; Private helper functions

;; Validate access type
(define-private (is-valid-access-type (access-type (string-ascii 20)))
    (or
        (is-eq access-type ACCESS-TYPE-READ)
        (is-eq access-type ACCESS-TYPE-WRITE)
        (is-eq access-type ACCESS-TYPE-DELETE)
        (is-eq access-type ACCESS-TYPE-EXPORT)
        (is-eq access-type ACCESS-TYPE-EMERGENCY)
    )
)

;; Validate severity level
(define-private (is-valid-severity (severity (string-ascii 10)))
    (or
        (is-eq severity SEVERITY-LOW)
        (is-eq severity SEVERITY-MEDIUM)
        (is-eq severity SEVERITY-HIGH)
        (is-eq severity SEVERITY-CRITICAL)
    )
)

;; Update access patterns for anomaly detection
(define-private (update-access-patterns (access-type (string-ascii 20)) (current-block uint))
    (let 
        (
            (date-key (/ current-block u144)) ;; Group by day (144 blocks ~= 1 day)
            (pattern-key {provider: tx-sender, date-block: date-key})
            (current-pattern (default-to 
                {
                    read-count: u0,
                    write-count: u0,
                    delete-count: u0,
                    export-count: u0,
                    emergency-count: u0,
                    peak-hour-access: u0,
                    unusual-location-access: u0
                }
                (map-get? access-patterns pattern-key)
            ))
        )
        
        ;; Update counters based on access type
        (map-set access-patterns pattern-key
            (if (is-eq access-type ACCESS-TYPE-READ)
                (merge current-pattern {read-count: (+ (get read-count current-pattern) u1)})
                (if (is-eq access-type ACCESS-TYPE-WRITE)
                    (merge current-pattern {write-count: (+ (get write-count current-pattern) u1)})
                    (if (is-eq access-type ACCESS-TYPE-DELETE)
                        (merge current-pattern {delete-count: (+ (get delete-count current-pattern) u1)})
                        (if (is-eq access-type ACCESS-TYPE-EXPORT)
                            (merge current-pattern {export-count: (+ (get export-count current-pattern) u1)})
                            (merge current-pattern {emergency-count: (+ (get emergency-count current-pattern) u1)})
                        )
                    )
                )
            )
        )
        
        true
    )
)

;; Update provider audit summary
(define-private (update-provider-summary)
    (let 
        (
            (current-summary (default-to 
                {
                    total-access-events: u0,
                    last-audit-date: u0,
                    violation-count: u0,
                    compliance-score: u100,
                    high-risk-flags: u0,
                    audit-period-start: stacks-block-height
                }
                (map-get? provider-audit-summary tx-sender)
            ))
        )
        
        (map-set provider-audit-summary tx-sender
            (merge current-summary 
                {
                    total-access-events: (+ (get total-access-events current-summary) u1)
                }
            )
        )
        
        true
    )
)

;; Update violation count in provider summary
(define-private (update-violation-count)
    (let 
        (
            (current-summary (default-to 
                {
                    total-access-events: u0,
                    last-audit-date: u0,
                    violation-count: u0,
                    compliance-score: u100,
                    high-risk-flags: u0,
                    audit-period-start: stacks-block-height
                }
                (map-get? provider-audit-summary tx-sender)
            ))
        )
        
        (map-set provider-audit-summary tx-sender
            (merge current-summary 
                {
                    violation-count: (+ (get violation-count current-summary) u1),
                    compliance-score: (if (> (get compliance-score current-summary) u10) 
                        (- (get compliance-score current-summary) u10) 
                        u0)
                }
            )
        )
        
        true
    )
)

;; Check for potential compliance violations
(define-private (check-compliance-violations 
    (event-id uint)
    (access-type (string-ascii 20))
    (data-exported bool)
    (emergency-override bool))
    
    (begin
        ;; Check for suspicious data export patterns
        (if (and data-exported (not emergency-override))
            (report-violation 
                "Unusual data export detected"
                SEVERITY-MEDIUM
                "Data export without emergency justification"
                event-id)
            (ok u0)
        )
    )
)

;; Read-only functions

;; Get audit event details
(define-read-only (get-audit-event (event-id uint))
    (ok (map-get? audit-events event-id))
)

;; Get compliance violation details
(define-read-only (get-violation (violation-id uint))
    (ok (map-get? compliance-violations violation-id))
)

;; Get provider audit summary
(define-read-only (get-provider-summary (provider principal))
    (ok (map-get? provider-audit-summary provider))
)

;; Get access patterns for anomaly analysis
(define-read-only (get-access-patterns (provider principal) (date-block uint))
    (ok (map-get? access-patterns {provider: provider, date-block: date-block}))
)

;; Get audit configuration
(define-read-only (get-audit-config (provider principal))
    (ok (map-get? audit-config provider))
)

;; Calculate compliance score based on violations and access patterns
(define-read-only (calculate-compliance-score (provider principal))
    (match (map-get? provider-audit-summary provider)
        summary (ok (get compliance-score summary))
        (ok u100) ;; Default perfect score for new providers
    )
)


