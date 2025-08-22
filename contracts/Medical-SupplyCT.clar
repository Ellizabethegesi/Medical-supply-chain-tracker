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

(define-constant ROLE-MANUFACTURER u1)
(define-constant ROLE-DISTRIBUTOR u2)
(define-constant ROLE-PHARMACY u3)
(define-constant ROLE-HOSPITAL u4)
(define-constant ROLE-REGULATOR u5)

(define-data-var contract-owner principal tx-sender)
(define-data-var product-id-nonce uint u0)

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
     (recipient-role (default-to u0 (map-get? user-roles to))))
    
    (asserts! (is-eq tx-sender (get current-owner product)) ERR-INVALID-OWNER)
    (asserts! (>= user-role ROLE-MANUFACTURER) ERR-NOT-AUTHORIZED)
    (asserts! (>= recipient-role ROLE-MANUFACTURER) ERR-NOT-AUTHORIZED)
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
    (ok new-sequence)
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

(map-set user-roles (var-get contract-owner) ROLE-REGULATOR)
