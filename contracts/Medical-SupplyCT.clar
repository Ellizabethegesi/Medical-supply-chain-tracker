;; title: Medical-SupplyCT
;; version: 1.0
;; summary: Medical Supply Chain Tracker for authenticity and chain of custody
;; description: Track vaccines and medicines through supply chain ensuring authenticity

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PRODUCT-EXISTS (err u101))
(define-constant ERR-PRODUCT-NOT-FOUND (err u102))
(define-constant ERR-INVALID-OWNER (err u103))
(define-constant ERR-EXPIRED-PRODUCT (err u104))
(define-constant ERR-INVALID-ROLE (err u105))
(define-constant ERR-ALREADY-VERIFIED (err u106))
(define-constant ERR-TEMP-TOO-LOW (err u107))
(define-constant ERR-TEMP-TOO-HIGH (err u108))
(define-constant ERR-TEMP-RANGE-NOT-SET (err u109))
(define-constant ERR-INVALID-TEMP-RANGE (err u110))
(define-constant ERR-PRODUCT-LOCKED (err u111))
(define-constant ERR-INVALID-THRESHOLD (err u112))
(define-constant ERR-INSUFFICIENT-QUANTITY (err u113))
(define-constant ERR-INVALID-QUANTITY (err u114))

(define-constant EXPIRY-STATUS-EXPIRED u1)
(define-constant EXPIRY-STATUS-CRITICAL u2)
(define-constant EXPIRY-STATUS-WARNING u3)
(define-constant EXPIRY-STATUS-SAFE u4)

(define-constant ROLE-MANUFACTURER u1)
(define-constant ROLE-DISTRIBUTOR u2)
(define-constant ROLE-PHARMACY u3)
(define-constant ROLE-HOSPITAL u4)
(define-constant ROLE-REGULATOR u5)

(define-data-var contract-owner principal tx-sender)
(define-data-var product-id-nonce uint u0)
(define-data-var temp-alert-counter uint u0)
(define-data-var analytics-enabled bool true)
(define-data-var expiry-warning-threshold uint u1008)
(define-data-var expiry-critical-threshold uint u144)

(define-map user-roles principal uint)

(define-map products
  uint
  {
    id: uint,
    name: (string-ascii 64),
    batch-number: (string-ascii 32),
    manufacturer: principal,
    manufacture-date: uint,
    expiry-date: uint,
    current-owner: principal,
    verified: bool,
    created-at: uint
  }
)

(define-map product-history
  { product-id: uint, sequence: uint }
  {
    from: principal,
    to: principal,
    timestamp: uint,
    location: (string-ascii 64),
    temperature: (optional int),
    notes: (string-ascii 128)
  }
)

(define-map product-sequence-counter uint uint)

(define-map batch-authenticity
  (string-ascii 32)
  {
    manufacturer: principal,
    authentic: bool,
    verified-by: principal,
    verified-at: uint
  }
)

(define-map product-temp-thresholds
  uint
  {
    min-temp: int,
    max-temp: int
  }
)

(define-map temp-alerts
  uint
  {
    product-id: uint,
    recorded-temp: int,
    timestamp: uint,
    reporter: principal,
    violation-type: (string-ascii 16)
  }
)

(define-map product-temp-compliance
  uint
  bool
)

(define-map product-locked
  uint
  bool
)

(define-map supply-chain-metrics
  { role: uint, period: uint }
  {
    total-transfers: uint,
    avg-transit-time: uint,
    temp-violations: uint,
    products-handled: uint
  }
)

(define-map global-analytics
  (string-ascii 32)
  uint
)

(define-map transit-performance
  { from-role: uint, to-role: uint }
  {
    total-transfers: uint,
    total-transit-time: uint,
    fastest-transit: uint,
    slowest-transit: uint
  }
)

(define-map compliance-stats
  uint
  {
    compliant-transfers: uint,
    total-transfers: uint,
    violation-count: uint,
    last-updated: uint
  }
)

(define-map expiry-notifications
  uint
  {
    product-id: uint,
    notified-at: uint,
    status: uint,
    notifier: principal
  }
)

(define-map batch-expiry-summary
  (string-ascii 32)
  {
    total-products: uint,
    expired-count: uint,
    critical-count: uint,
    warning-count: uint,
    safe-count: uint,
    last-updated: uint
  }
)

(define-map product-inventory
  uint
  {
    total-quantity: uint,
    available-quantity: uint,
    reserved-quantity: uint,
    unit-type: (string-ascii 16),
    last-updated: uint
  }
)

(define-map inventory-by-owner
  { product-id: uint, owner: principal }
  uint
)

(define-map inventory-reservations
  { product-id: uint, reserver: principal }
  {
    quantity: uint,
    reserved-at: uint,
    expires-at: uint
  }
)

(define-data-var reservation-duration uint u144)

(define-public (set-user-role (user principal) (role uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (<= role ROLE-REGULATOR) ERR-INVALID-ROLE)
    (ok (map-set user-roles user role))
  )
)

(define-public (register-product 
  (name (string-ascii 64))
  (batch-number (string-ascii 32))
  (manufacture-date uint)
  (expiry-date uint)
  (initial-location (string-ascii 64)))
  (let
    ((product-id (+ (var-get product-id-nonce) u1))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    (asserts! (is-eq user-role ROLE-MANUFACTURER) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? products product-id)) ERR-PRODUCT-EXISTS)
    (asserts! (< manufacture-date expiry-date) ERR-EXPIRED-PRODUCT)
    
    (map-set products product-id {
      id: product-id,
      name: name,
      batch-number: batch-number,
      manufacturer: tx-sender,
      manufacture-date: manufacture-date,
      expiry-date: expiry-date,
      current-owner: tx-sender,
      verified: false,
      created-at: stacks-block-height
    })
    
    (map-set product-history 
      { product-id: product-id, sequence: u0 }
      {
        from: tx-sender,
        to: tx-sender,
        timestamp: stacks-block-height,
        location: initial-location,
        temperature: none,
        notes: "Product manufactured"
      }
    )
    
    (map-set product-sequence-counter product-id u0)
    (var-set product-id-nonce product-id)
    (ok product-id)
  )
)

(define-private (update-analytics 
  (product-id uint)
  (from-role uint)
  (to-role uint)
  (transit-time uint)
  (temp-compliant bool))
  (begin
    (if (var-get analytics-enabled)
      (begin
        (let
          ((period (/ stacks-block-height u144))
           (from-metrics (default-to { total-transfers: u0, avg-transit-time: u0, temp-violations: u0, products-handled: u0 }
                           (map-get? supply-chain-metrics { role: from-role, period: period })))
           (to-metrics (default-to { total-transfers: u0, avg-transit-time: u0, temp-violations: u0, products-handled: u0 }
                         (map-get? supply-chain-metrics { role: to-role, period: period })))
           (transit-key { from-role: from-role, to-role: to-role })
           (transit-perf (default-to { total-transfers: u0, total-transit-time: u0, fastest-transit: u999999, slowest-transit: u0 }
                           (map-get? transit-performance transit-key)))
           (compliance (default-to { compliant-transfers: u0, total-transfers: u0, violation-count: u0, last-updated: u0 }
                        (map-get? compliance-stats product-id))))
          
          (map-set supply-chain-metrics { role: from-role, period: period } {
            total-transfers: (+ (get total-transfers from-metrics) u1),
            avg-transit-time: (/ (+ (* (get avg-transit-time from-metrics) (get total-transfers from-metrics)) transit-time)
                               (+ (get total-transfers from-metrics) u1)),
            temp-violations: (+ (get temp-violations from-metrics) (if temp-compliant u0 u1)),
            products-handled: (+ (get products-handled from-metrics) u1)
          })
          
          (map-set transit-performance transit-key {
            total-transfers: (+ (get total-transfers transit-perf) u1),
            total-transit-time: (+ (get total-transit-time transit-perf) transit-time),
            fastest-transit: (if (< transit-time (get fastest-transit transit-perf)) transit-time (get fastest-transit transit-perf)),
            slowest-transit: (if (> transit-time (get slowest-transit transit-perf)) transit-time (get slowest-transit transit-perf))
          })
          
          (map-set compliance-stats product-id {
            compliant-transfers: (+ (get compliant-transfers compliance) (if temp-compliant u1 u0)),
            total-transfers: (+ (get total-transfers compliance) u1),
            violation-count: (+ (get violation-count compliance) (if temp-compliant u0 u1)),
            last-updated: stacks-block-height
          })
          
          (map-set global-analytics "total-transfers" 
            (+ (default-to u0 (map-get? global-analytics "total-transfers")) u1))
          (map-set global-analytics "temp-violations" 
            (+ (default-to u0 (map-get? global-analytics "temp-violations")) (if temp-compliant u0 u1)))
        )
        (ok true)
      )
      (ok true)
    )
  )
)

(define-public (transfer-product
  (product-id uint)
  (to principal)
  (location (string-ascii 64))
  (temperature (optional int))
  (notes (string-ascii 128)))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (current-sequence (default-to u0 (map-get? product-sequence-counter product-id)))
     (new-sequence (+ current-sequence u1))
     (user-role (default-to u0 (map-get? user-roles tx-sender)))
     (recipient-role (default-to u0 (map-get? user-roles to)))
     (locked (default-to false (map-get? product-locked product-id))))
    
    (asserts! (is-eq tx-sender (get current-owner product)) ERR-INVALID-OWNER)
    (asserts! (>= user-role ROLE-MANUFACTURER) ERR-NOT-AUTHORIZED)
    (asserts! (>= recipient-role ROLE-MANUFACTURER) ERR-NOT-AUTHORIZED)
    (asserts! (not locked) ERR-PRODUCT-LOCKED)
    (asserts! (< stacks-block-height (get expiry-date product)) ERR-EXPIRED-PRODUCT)
    
    (map-set products product-id 
      (merge product { current-owner: to }))
    
    (map-set product-history
      { product-id: product-id, sequence: new-sequence }
      {
        from: tx-sender,
        to: to,
        timestamp: stacks-block-height,
        location: location,
        temperature: temperature,
        notes: notes
      }
    )
    
    (map-set product-sequence-counter product-id new-sequence)
    
    (let
      ((last-transfer-time (match (map-get? product-history { product-id: product-id, sequence: current-sequence })
          history (get timestamp history)
          stacks-block-height))
       (transit-time (- stacks-block-height last-transfer-time))
       (temp-compliant (is-some temperature)))
      
      (unwrap-panic (update-analytics product-id user-role recipient-role transit-time temp-compliant))
      (ok new-sequence)
    )
  )
)

(define-public (verify-product-authenticity (product-id uint))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    
    (asserts! (is-eq user-role ROLE-REGULATOR) ERR-NOT-AUTHORIZED)
    (asserts! (not (get verified product)) ERR-ALREADY-VERIFIED)
    
    (map-set products product-id 
      (merge product { verified: true }))
    
    (map-set batch-authenticity (get batch-number product) {
      manufacturer: (get manufacturer product),
      authentic: true,
      verified-by: tx-sender,
      verified-at: stacks-block-height
    })
    
    (ok true)
  )
)

(define-public (report-counterfeit (batch-number (string-ascii 32)))
  (let
    ((user-role (default-to u0 (map-get? user-roles tx-sender))))
    
    (asserts! (>= user-role ROLE-PHARMACY) ERR-NOT-AUTHORIZED)
    
    (map-set batch-authenticity batch-number {
      manufacturer: tx-sender,
      authentic: false,
      verified-by: tx-sender,
      verified-at: stacks-block-height
    })
    
    (ok true)
  )
)

(define-public (recall-product (product-id uint) (reason (string-ascii 128)))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    
    (asserts! (or 
      (is-eq tx-sender (get manufacturer product))
      (is-eq user-role ROLE-REGULATOR)) ERR-NOT-AUTHORIZED)
    
    (let
      ((current-sequence (default-to u0 (map-get? product-sequence-counter product-id)))
       (new-sequence (+ current-sequence u1)))
      
      (map-set product-history
        { product-id: product-id, sequence: new-sequence }
        {
          from: (get current-owner product),
          to: (get manufacturer product),
          timestamp: stacks-block-height,
          location: "RECALLED",
          temperature: none,
          notes: reason
        }
      )
      
      (map-set products product-id 
        (merge product { current-owner: (get manufacturer product) }))
      
      (map-set product-sequence-counter product-id new-sequence)
      (ok new-sequence)
    )
  )
)

(define-public (lock-product (product-id uint))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    (asserts! (or
      (is-eq tx-sender (var-get contract-owner))
      (is-eq user-role ROLE-REGULATOR)
      (and (is-eq user-role ROLE-MANUFACTURER) (is-eq tx-sender (get manufacturer product)))) ERR-NOT-AUTHORIZED)
    (map-set product-locked product-id true)
    (ok true)
  )
)

(define-public (unlock-product (product-id uint))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    (asserts! (or
      (is-eq tx-sender (var-get contract-owner))
      (is-eq user-role ROLE-REGULATOR)
      (and (is-eq user-role ROLE-MANUFACTURER) (is-eq tx-sender (get manufacturer product)))) ERR-NOT-AUTHORIZED)
    (map-set product-locked product-id false)
    (ok true)
  )
)

(define-read-only (is-product-locked (product-id uint))
  (default-to false (map-get? product-locked product-id))
)

(define-read-only (get-product (product-id uint))
  (map-get? products product-id)
)

(define-read-only (get-product-history (product-id uint) (sequence uint))
  (map-get? product-history { product-id: product-id, sequence: sequence })
)

(define-read-only (get-batch-authenticity (batch-number (string-ascii 32)))
  (map-get? batch-authenticity batch-number)
)

(define-read-only (get-user-role (user principal))
  (default-to u0 (map-get? user-roles user))
)

(define-read-only (is-product-expired (product-id uint))
  (match (map-get? products product-id)
    product (>= stacks-block-height (get expiry-date product))
    true
  )
)

(define-read-only (get-products-by-owner (owner principal))
  (ok owner)
)

(define-read-only (verify-chain-of-custody (product-id uint))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND)))
    (ok {
      product-verified: (get verified product),
      batch-authentic: (is-some (map-get? batch-authenticity (get batch-number product))),
      not-expired: (< stacks-block-height (get expiry-date product)),
      manufacturer: (get manufacturer product)
    })
  )
)

(define-read-only (get-product-history-count (product-id uint))
  (default-to u0 (map-get? product-sequence-counter product-id))
)

(define-public (set-temp-threshold (product-id uint) (min-temp int) (max-temp int))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    
    (asserts! (or
      (is-eq tx-sender (var-get contract-owner))
      (and (is-eq user-role ROLE-MANUFACTURER) (is-eq tx-sender (get manufacturer product)))
      (is-eq user-role ROLE-REGULATOR)) ERR-NOT-AUTHORIZED)
    (asserts! (<= min-temp max-temp) ERR-INVALID-TEMP-RANGE)
    
    (map-set product-temp-thresholds product-id {
      min-temp: min-temp,
      max-temp: max-temp
    })
    
    (ok true)
  )
)

(define-public (record-temperature (product-id uint) (temp int))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (thresholds (unwrap! (map-get? product-temp-thresholds product-id) ERR-TEMP-RANGE-NOT-SET))
     (user-role (default-to u0 (map-get? user-roles tx-sender)))
     (min-temp (get min-temp thresholds))
     (max-temp (get max-temp thresholds))
     (locked (default-to false (map-get? product-locked product-id))))
    
    (asserts! (>= user-role ROLE-DISTRIBUTOR) ERR-NOT-AUTHORIZED)
    (asserts! (not locked) ERR-PRODUCT-LOCKED)
    
    (if (and (>= temp min-temp) (<= temp max-temp))
      (begin
        (map-set product-temp-compliance product-id true)
        (ok true)
      )
      (begin
        (map-set product-temp-compliance product-id false)
        (let
          ((alert-id (+ (var-get temp-alert-counter) u1))
           (violation-type (if (< temp min-temp) "LOW" "HIGH")))
          
          (map-set temp-alerts alert-id {
            product-id: product-id,
            recorded-temp: temp,
            timestamp: stacks-block-height,
            reporter: tx-sender,
            violation-type: violation-type
          })
          
          (var-set temp-alert-counter alert-id)
          
          (if (< temp min-temp)
            ERR-TEMP-TOO-LOW
            ERR-TEMP-TOO-HIGH
          )
        )
      )
    )
  )
)

(define-read-only (get-temp-threshold (product-id uint))
  (map-get? product-temp-thresholds product-id)
)

(define-read-only (get-temp-alert (alert-id uint))
  (map-get? temp-alerts alert-id)
)

(define-read-only (is-product-temp-compliant (product-id uint))
  (default-to true (map-get? product-temp-compliance product-id))
)

(define-read-only (get-temp-alert-count)
  (var-get temp-alert-counter)
)

(define-read-only (get-supply-chain-metrics (role uint) (period uint))
  (map-get? supply-chain-metrics { role: role, period: period })
)

(define-read-only (get-transit-performance (from-role uint) (to-role uint))
  (map-get? transit-performance { from-role: from-role, to-role: to-role })
)

(define-read-only (get-compliance-stats (product-id uint))
  (map-get? compliance-stats product-id)
)

(define-read-only (get-global-analytics (metric (string-ascii 32)))
  (default-to u0 (map-get? global-analytics metric))
)

(define-read-only (get-role-efficiency (role uint) (period uint))
  (match (map-get? supply-chain-metrics { role: role, period: period })
    metrics
    (ok {
      efficiency-score: (if (> (get total-transfers metrics) u0)
        (/ (* (get products-handled metrics) u100) (get total-transfers metrics))
        u0),
      violation-rate: (if (> (get products-handled metrics) u0)
        (/ (* (get temp-violations metrics) u100) (get products-handled metrics))
        u0),
      avg-transit-time: (get avg-transit-time metrics),
      total-handled: (get products-handled metrics)
    })
    (ok { efficiency-score: u0, violation-rate: u0, avg-transit-time: u0, total-handled: u0 })
  )
)

(define-read-only (get-supply-chain-health)
  (let
    ((total-transfers (get-global-analytics "total-transfers"))
     (total-violations (get-global-analytics "temp-violations")))
    (ok {
      total-transfers: total-transfers,
      total-violations: total-violations,
      compliance-rate: (if (> total-transfers u0)
        (/ (* (- total-transfers total-violations) u100) total-transfers)
        u100),
      violation-rate: (if (> total-transfers u0)
        (/ (* total-violations u100) total-transfers)
        u0)
    })
  )
)

(define-read-only (get-fastest-route (from-role uint) (to-role uint))
  (match (map-get? transit-performance { from-role: from-role, to-role: to-role })
    perf
    (ok {
      fastest-time: (get fastest-transit perf),
      slowest-time: (get slowest-transit perf),
      avg-time: (if (> (get total-transfers perf) u0)
        (/ (get total-transit-time perf) (get total-transfers perf))
        u0),
      total-transfers: (get total-transfers perf)
    })
    (ok { fastest-time: u0, slowest-time: u0, avg-time: u0, total-transfers: u0 })
  )
)

(define-public (toggle-analytics)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set analytics-enabled (not (var-get analytics-enabled)))
    (ok (var-get analytics-enabled))
  )
)

(define-public (set-expiry-thresholds (warning-blocks uint) (critical-blocks uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> warning-blocks critical-blocks) ERR-INVALID-THRESHOLD)
    (var-set expiry-warning-threshold warning-blocks)
    (var-set expiry-critical-threshold critical-blocks)
    (ok true)
  )
)

(define-public (check-product-expiry (product-id uint))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (expiry-date (get expiry-date product))
     (blocks-until-expiry (if (> expiry-date stacks-block-height) 
                             (- expiry-date stacks-block-height) 
                             u0))
     (status (get-expiry-status-value expiry-date)))
    
    (map-set expiry-notifications product-id {
      product-id: product-id,
      notified-at: stacks-block-height,
      status: status,
      notifier: tx-sender
    })
    
    (ok {
      product-id: product-id,
      expiry-date: expiry-date,
      blocks-remaining: blocks-until-expiry,
      status: status,
      status-label: (get-expiry-label status)
    })
  )
)

(define-public (update-batch-expiry-summary (batch-number (string-ascii 32)) (product-id uint))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (current-summary (default-to 
       { total-products: u0, expired-count: u0, critical-count: u0, warning-count: u0, safe-count: u0, last-updated: u0 }
       (map-get? batch-expiry-summary batch-number)))
     (status (get-expiry-status-value (get expiry-date product))))
    
    (asserts! (is-eq batch-number (get batch-number product)) ERR-PRODUCT-NOT-FOUND)
    
    (map-set batch-expiry-summary batch-number {
      total-products: (+ (get total-products current-summary) u1),
      expired-count: (+ (get expired-count current-summary) (if (is-eq status EXPIRY-STATUS-EXPIRED) u1 u0)),
      critical-count: (+ (get critical-count current-summary) (if (is-eq status EXPIRY-STATUS-CRITICAL) u1 u0)),
      warning-count: (+ (get warning-count current-summary) (if (is-eq status EXPIRY-STATUS-WARNING) u1 u0)),
      safe-count: (+ (get safe-count current-summary) (if (is-eq status EXPIRY-STATUS-SAFE) u1 u0)),
      last-updated: stacks-block-height
    })
    
    (ok status)
  )
)

(define-private (get-expiry-status-value (expiry-date uint))
  (if (<= expiry-date stacks-block-height)
    EXPIRY-STATUS-EXPIRED
    (if (<= (- expiry-date stacks-block-height) (var-get expiry-critical-threshold))
      EXPIRY-STATUS-CRITICAL
      (if (<= (- expiry-date stacks-block-height) (var-get expiry-warning-threshold))
        EXPIRY-STATUS-WARNING
        EXPIRY-STATUS-SAFE
      )
    )
  )
)

(define-private (get-expiry-label (status uint))
  (if (is-eq status EXPIRY-STATUS-EXPIRED)
    "EXPIRED"
    (if (is-eq status EXPIRY-STATUS-CRITICAL)
      "CRITICAL"
      (if (is-eq status EXPIRY-STATUS-WARNING)
        "WARNING"
        "SAFE"
      )
    )
  )
)

(define-read-only (get-expiry-thresholds)
  {
    warning-threshold: (var-get expiry-warning-threshold),
    critical-threshold: (var-get expiry-critical-threshold)
  }
)

(define-read-only (get-product-expiry-status (product-id uint))
  (match (map-get? products product-id)
    product
    (let
      ((expiry-date (get expiry-date product))
       (status (get-expiry-status-value expiry-date)))
      (ok {
        product-id: product-id,
        name: (get name product),
        batch-number: (get batch-number product),
        expiry-date: expiry-date,
        blocks-remaining: (if (> expiry-date stacks-block-height) 
                            (- expiry-date stacks-block-height) 
                            u0),
        status: status,
        status-label: (get-expiry-label status)
      })
    )
    ERR-PRODUCT-NOT-FOUND
  )
)

(define-read-only (get-batch-expiry-summary (batch-number (string-ascii 32)))
  (map-get? batch-expiry-summary batch-number)
)

(define-read-only (get-expiry-notification (product-id uint))
  (map-get? expiry-notifications product-id)
)

(define-read-only (is-product-near-expiry (product-id uint))
  (match (map-get? products product-id)
    product
    (let
      ((status (get-expiry-status-value (get expiry-date product))))
      (or (is-eq status EXPIRY-STATUS-EXPIRED) 
          (is-eq status EXPIRY-STATUS-CRITICAL)
          (is-eq status EXPIRY-STATUS-WARNING))
    )
    true
  )
)

(define-public (initialize-inventory 
  (product-id uint) 
  (quantity uint) 
  (unit-type (string-ascii 16)))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    
    (asserts! (is-eq tx-sender (get manufacturer product)) ERR-NOT-AUTHORIZED)
    (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
    
    (map-set product-inventory product-id {
      total-quantity: quantity,
      available-quantity: quantity,
      reserved-quantity: u0,
      unit-type: unit-type,
      last-updated: stacks-block-height
    })
    
    (map-set inventory-by-owner { product-id: product-id, owner: tx-sender } quantity)
    (ok true)
  )
)

(define-public (transfer-quantity
  (product-id uint)
  (to principal)
  (quantity uint)
  (location (string-ascii 64))
  (notes (string-ascii 128)))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (inventory (unwrap! (map-get? product-inventory product-id) ERR-PRODUCT-NOT-FOUND))
     (sender-qty (default-to u0 (map-get? inventory-by-owner { product-id: product-id, owner: tx-sender })))
     (recipient-qty (default-to u0 (map-get? inventory-by-owner { product-id: product-id, owner: to })))
     (user-role (default-to u0 (map-get? user-roles tx-sender)))
     (recipient-role (default-to u0 (map-get? user-roles to)))
     (locked (default-to false (map-get? product-locked product-id))))
    
    (asserts! (>= user-role ROLE-MANUFACTURER) ERR-NOT-AUTHORIZED)
    (asserts! (>= recipient-role ROLE-MANUFACTURER) ERR-NOT-AUTHORIZED)
    (asserts! (not locked) ERR-PRODUCT-LOCKED)
    (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
    (asserts! (>= sender-qty quantity) ERR-INSUFFICIENT-QUANTITY)
    (asserts! (< stacks-block-height (get expiry-date product)) ERR-EXPIRED-PRODUCT)
    
    (map-set inventory-by-owner { product-id: product-id, owner: tx-sender } (- sender-qty quantity))
    (map-set inventory-by-owner { product-id: product-id, owner: to } (+ recipient-qty quantity))
    
    (let
      ((current-sequence (default-to u0 (map-get? product-sequence-counter product-id)))
       (new-sequence (+ current-sequence u1)))
      
      (map-set product-history
        { product-id: product-id, sequence: new-sequence }
        {
          from: tx-sender,
          to: to,
          timestamp: stacks-block-height,
          location: location,
          temperature: none,
          notes: notes
        }
      )
      
      (map-set product-sequence-counter product-id new-sequence)
      (ok { sequence: new-sequence, quantity-transferred: quantity })
    )
  )
)

(define-public (reserve-inventory (product-id uint) (quantity uint))
  (let
    ((inventory (unwrap! (map-get? product-inventory product-id) ERR-PRODUCT-NOT-FOUND))
     (available (get available-quantity inventory))
     (reserved (get reserved-quantity inventory))
     (user-role (default-to u0 (map-get? user-roles tx-sender))))
    
    (asserts! (>= user-role ROLE-DISTRIBUTOR) ERR-NOT-AUTHORIZED)
    (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
    (asserts! (>= available quantity) ERR-INSUFFICIENT-QUANTITY)
    
    (map-set product-inventory product-id (merge inventory {
      available-quantity: (- available quantity),
      reserved-quantity: (+ reserved quantity),
      last-updated: stacks-block-height
    }))
    
    (map-set inventory-reservations { product-id: product-id, reserver: tx-sender } {
      quantity: quantity,
      reserved-at: stacks-block-height,
      expires-at: (+ stacks-block-height (var-get reservation-duration))
    })
    
    (ok true)
  )
)

(define-public (release-reservation (product-id uint))
  (let
    ((inventory (unwrap! (map-get? product-inventory product-id) ERR-PRODUCT-NOT-FOUND))
     (reservation (unwrap! (map-get? inventory-reservations { product-id: product-id, reserver: tx-sender }) ERR-PRODUCT-NOT-FOUND))
     (reserved-qty (get quantity reservation))
     (available (get available-quantity inventory))
     (total-reserved (get reserved-quantity inventory)))
    
    (map-set product-inventory product-id (merge inventory {
      available-quantity: (+ available reserved-qty),
      reserved-quantity: (- total-reserved reserved-qty),
      last-updated: stacks-block-height
    }))
    
    (map-delete inventory-reservations { product-id: product-id, reserver: tx-sender })
    (ok reserved-qty)
  )
)

(define-public (adjust-inventory (product-id uint) (new-quantity uint) (reason (string-ascii 128)))
  (let
    ((product (unwrap! (map-get? products product-id) ERR-PRODUCT-NOT-FOUND))
     (inventory (unwrap! (map-get? product-inventory product-id) ERR-PRODUCT-NOT-FOUND))
     (user-role (default-to u0 (map-get? user-roles tx-sender)))
     (current-total (get total-quantity inventory))
     (current-available (get available-quantity inventory))
     (current-reserved (get reserved-quantity inventory)))
    
    (asserts! (or
      (is-eq tx-sender (get manufacturer product))
      (is-eq user-role ROLE-REGULATOR)) ERR-NOT-AUTHORIZED)
    (asserts! (>= new-quantity current-reserved) ERR-INSUFFICIENT-QUANTITY)
    
    (let
      ((current-sequence (default-to u0 (map-get? product-sequence-counter product-id)))
       (new-sequence (+ current-sequence u1)))
      
      (map-set product-inventory product-id {
        total-quantity: new-quantity,
        available-quantity: (- new-quantity current-reserved),
        reserved-quantity: current-reserved,
        unit-type: (get unit-type inventory),
        last-updated: stacks-block-height
      })
      
      (map-set product-history
        { product-id: product-id, sequence: new-sequence }
        {
          from: tx-sender,
          to: tx-sender,
          timestamp: stacks-block-height,
          location: "INVENTORY-ADJUSTMENT",
          temperature: none,
          notes: reason
        }
      )
      
      (map-set product-sequence-counter product-id new-sequence)
      (ok { old-quantity: current-total, new-quantity: new-quantity })
    )
  )
)

(define-public (set-reservation-duration (blocks uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> blocks u0) ERR-INVALID-QUANTITY)
    (var-set reservation-duration blocks)
    (ok true)
  )
)

(define-read-only (get-product-inventory (product-id uint))
  (map-get? product-inventory product-id)
)

(define-read-only (get-owner-quantity (product-id uint) (owner principal))
  (default-to u0 (map-get? inventory-by-owner { product-id: product-id, owner: owner }))
)

(define-read-only (get-reservation (product-id uint) (reserver principal))
  (map-get? inventory-reservations { product-id: product-id, reserver: reserver })
)

(define-read-only (is-reservation-expired (product-id uint) (reserver principal))
  (match (map-get? inventory-reservations { product-id: product-id, reserver: reserver })
    reservation (>= stacks-block-height (get expires-at reservation))
    true
  )
)

(define-read-only (get-inventory-summary (product-id uint))
  (match (map-get? product-inventory product-id)
    inventory
    (ok {
      total: (get total-quantity inventory),
      available: (get available-quantity inventory),
      reserved: (get reserved-quantity inventory),
      unit: (get unit-type inventory),
      utilization-rate: (if (> (get total-quantity inventory) u0)
        (/ (* (- (get total-quantity inventory) (get available-quantity inventory)) u100) (get total-quantity inventory))
        u0)
    })
    ERR-PRODUCT-NOT-FOUND
  )
)

(map-set user-roles (var-get contract-owner) ROLE-REGULATOR)
