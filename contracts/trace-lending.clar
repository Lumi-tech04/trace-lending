;; trace-lending
;; 
;; A decentralized lending platform built on Stacks that provides secure, transparent,
;; and efficient lending services with innovative reputation and risk management.

;; Error Handling Constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-LOAN-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-REPAYMENT-FAILED (err u104))
(define-constant ERR-COLLATERAL-INSUFFICIENT (err u105))
(define-constant ERR-USER-NOT-FOUND (err u106))
(define-constant ERR-ALREADY-EXISTS (err u107))
(define-constant ERR-LOAN-CLOSED (err u108))
(define-constant ERR-LIQUIDATION-IMPOSSIBLE (err u109))

;; Loan Status Constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-ACTIVE u2)
(define-constant STATUS-REPAID u3)
(define-constant STATUS-DEFAULTED u4)
(define-constant STATUS-LIQUIDATED u5)

;; Platform Configuration
(define-constant PLATFORM-FEE-BPS u25) ;; 2.5%
(define-constant MINIMUM-LOAN-AMOUNT u100) ;; Minimum loan amount
(define-constant MAXIMUM-LOAN-TERM u2102400) ;; ~2 years in blocks

;; Contract Owner
(define-data-var contract-owner principal tx-sender)

;; Core Data Maps

;; User Loan Profiles
(define-map user-profiles
  { user: principal }
  {
    total-loans-issued: uint,
    total-loans-borrowed: uint,
    total-repaid: uint,
    total-defaulted: uint,
    credit-score: uint,
    created-at: uint
  }
)

;; Loan Listings
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    lender: principal,
    total-amount: uint,
    remaining-amount: uint,
    interest-rate: uint,
    collateral-amount: uint,
    start-block: uint,
    due-block: uint,
    status: uint,
    liquidation-threshold: uint
  }
)

;; Repayment Tracking
(define-map loan-repayments
  { loan-id: uint }
  {
    total-repaid: uint,
    last-repayment-block: uint,
    next-payment-due: uint
  }
)

;; Loan Counter
(define-data-var loan-id-counter uint u0)

;; Platform Fee Wallet
(define-data-var fee-address principal tx-sender)

;; Private Helper Functions

;; Generate Next Loan ID
(define-private (get-next-loan-id)
  (let ((next-id (+ (var-get loan-id-counter) u1)))
    (var-set loan-id-counter next-id)
    next-id
  )
)

;; Calculate Platform Fee
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE-BPS) u1000)
)

;; Initialize User Profile
(define-private (init-user-profile (user principal))
  (match (map-get? user-profiles { user: user })
    profile true
    (map-set user-profiles
      { user: user }
      {
        total-loans-issued: u0,
        total-loans-borrowed: u0,
        total-repaid: u0,
        total-defaulted: u0,
        credit-score: u100,
        created-at: block-height
      }
    )
  )
)

;; Public Functions

;; Create a new loan listing
(define-public (create-loan 
  (total-amount uint)
  (interest-rate uint)
  (loan-term uint)
  (collateral-amount uint)
  (liquidation-threshold uint))
  (let (
    (loan-id (get-next-loan-id))
    (borrower tx-sender)
  )
    ;; Input validation
    (asserts! (>= total-amount MINIMUM-LOAN-AMOUNT) ERR-INSUFFICIENT-FUNDS)
    (asserts! (<= loan-term MAXIMUM-LOAN-TERM) ERR-INVALID-STATUS)
    (asserts! (>= collateral-amount (* total-amount u2)) ERR-COLLATERAL-INSUFFICIENT)
    
    ;; Transfer collateral to contract
    (try! (stx-transfer? collateral-amount borrower (as-contract tx-sender)))
    
    ;; Initialize user profile
    (init-user-profile borrower)
    
    ;; Create loan listing
    (map-set loans
      { loan-id: loan-id }
      {
        borrower: borrower,
        lender: tx-sender,
        total-amount: total-amount,
        remaining-amount: total-amount,
        interest-rate: interest-rate,
        collateral-amount: collateral-amount,
        start-block: block-height,
        due-block: (+ block-height loan-term),
        status: STATUS-PENDING,
        liquidation-threshold: liquidation-threshold
      }
    )
    
    (ok loan-id)
  )
)

;; Fund a loan
(define-public (fund-loan (loan-id uint))
  (let (
    (lender tx-sender)
    (loan (map-get? loans { loan-id: loan-id }))
  )
    ;; Validate loan exists and is pending
    (asserts! (is-some loan) ERR-LOAN-NOT-FOUND)
    (asserts! (is-eq (get status (unwrap-panic loan)) STATUS-PENDING) ERR-INVALID-STATUS)
    
    ;; Transfer loan amount to borrower
    (try! (stx-transfer? (get total-amount (unwrap-panic loan)) lender (get borrower (unwrap-panic loan))))
    
    ;; Update loan status
    (map-set loans
      { loan-id: loan-id }
      (merge (unwrap-panic loan)
        {
          lender: lender,
          status: STATUS-ACTIVE
        }
      )
    )
    
    (ok true)
  )
)

;; Repay loan
(define-public (repay-loan (loan-id uint) (repayment-amount uint))
  (let (
    (borrower tx-sender)
    (loan (map-get? loans { loan-id: loan-id }))
    (repayment-info (map-get? loan-repayments { loan-id: loan-id }))
  )
    ;; Validate loan exists and is active
    (asserts! (is-some loan) ERR-LOAN-NOT-FOUND)
    (asserts! (is-eq (get status (unwrap-panic loan)) STATUS-ACTIVE) ERR-INVALID-STATUS)
    (asserts! (is-eq borrower (get borrower (unwrap-panic loan))) ERR-UNAUTHORIZED)
    
    ;; Calculate interest and platform fee
    (let (
      (total-amount (get total-amount (unwrap-panic loan)))
      (interest-rate (get interest-rate (unwrap-panic loan)))
      (calculated-interest (/ (* total-amount interest-rate) u1000))
      (platform-fee (calculate-platform-fee repayment-amount))
      (net-repayment (- repayment-amount platform-fee))
    )
      ;; Transfer repayment to lender (including interest)
      (try! (stx-transfer? (+ net-repayment calculated-interest) borrower (get lender (unwrap-panic loan))))
      
      ;; Transfer platform fee
      (try! (stx-transfer? platform-fee borrower (var-get fee-address)))
      
      ;; Update loan repayment tracking
      (let ((updated-repayment-info (default-to 
        {
          total-repaid: u0,
          last-repayment-block: u0,
          next-payment-due: u0
        } 
        repayment-info)))
        (map-set loan-repayments
          { loan-id: loan-id }
          {
            total-repaid: (+ (get total-repaid updated-repayment-info) repayment-amount),
            last-repayment-block: block-height,
            next-payment-due: (+ block-height u100) ;; Simple payment interval
          }
        )
      )
      
      ;; Update loan status if fully repaid
      (if (>= (+ (get total-repaid (default-to { total-repaid: u0 } repayment-info)) repayment-amount) total-amount)
        (map-set loans
          { loan-id: loan-id }
          (merge (unwrap-panic loan)
            {
              status: STATUS-REPAID,
              remaining-amount: u0
            }
          )
        )
        true
      )
      
      (ok true)
    )
  )
)

;; Liquidate loan if collateral threshold is breached
(define-public (liquidate-loan (loan-id uint))
  (let (
    (loan (map-get? loans { loan-id: loan-id }))
  )
    ;; Validate loan exists and is active
    (asserts! (is-some loan) ERR-LOAN-NOT-FOUND)
    (asserts! (is-eq (get status (unwrap-panic loan)) STATUS-ACTIVE) ERR-INVALID-STATUS)
    
    ;; Check if liquidation is possible
    (asserts! 
      (< (stx-get-balance (get borrower (unwrap-panic loan))) 
         (get liquidation-threshold (unwrap-panic loan))) 
      ERR-LIQUIDATION-IMPOSSIBLE)
    
    ;; Transfer collateral to lender
    (try! (as-contract (stx-transfer? 
      (get collateral-amount (unwrap-panic loan)) 
      tx-sender 
      (get lender (unwrap-panic loan))
    )))
    
    ;; Update loan status
    (map-set loans
      { loan-id: loan-id }
      (merge (unwrap-panic loan)
        {
          status: STATUS-LIQUIDATED,
          remaining-amount: u0
        }
      )
    )
    
    (ok true)
  )
)

;; Read-only Functions

;; Get Loan Details
(define-read-only (get-loan-details (loan-id uint))
  (map-get? loans { loan-id: loan-id })
)

;; Get User Profile
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)