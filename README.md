# ArtisanProvenance

A blockchain-based digital art authenticity and provenance tracking system built on Stacks. This smart contract enables artists to mint authenticated artworks with verifiable ownership history and gallery approval ratings.

## Features

- **Artist Studio Registration**: Artists can register their studios and get verified status
- **Artwork Minting**: Mint unique digital artworks as NFTs with metadata
- **Provenance Tracking**: Complete ownership history for each artwork
- **Gallery Approval System**: Galleries can rate and approve artworks
- **Attribute Management**: Set detailed traits and characteristics for artworks

## Smart Contract Functions

### Administrative
- `update-platform-admin`: Update the platform administrator
- `register-artist-studio`: Register and verify artist studios
- `deactivate-artist-studio`: Deactivate artist studio verification

### Artwork Management
- `mint-artwork`: Create new authenticated artwork NFTs
- `transfer-artwork`: Transfer artwork ownership
- `set-artwork-attributes`: Define artwork traits and characteristics

### Gallery System
- `set-gallery-approval`: Set gallery approval and rating for artworks

### Query Functions
- `get-artwork-metadata`: Retrieve artwork details
- `get-artwork-attributes`: Get artwork traits
- `get-gallery-approval`: Check gallery approval status
- `get-artist-studio`: Get artist studio information
- `is-artist-verified`: Check artist verification status

## Getting Started

1. Deploy the contract to Stacks blockchain
2. Register as an artist studio using `register-artist-studio`
3. Mint artworks with `mint-artwork`
4. Set artwork attributes and get gallery approvals

## License

MIT License
\`\`\`

```clarity file="project-2-supply-guardian/contracts/supply-guardian.clar"
;; SupplyGuardian - Supply chain authenticity and traceability system
;; This contract enables manufacturers to create verifiable product authenticity certificates

(define-non-fungible-token product-certificate uint)

;; Data storage
(define-map product-info uint {brand: (string-ascii 64), description: (string-ascii 256), qr-code: (string-utf8 256)})
(define-map product-specs uint (list 20 {component: (string-ascii 32), specification: (string-ascii 64)}))
(define-map manufacturer-registry principal {company-name: (string-ascii 64), authorized: bool})
(define-map inspector-product-validation {inspector-id: principal, product-id: uint} {validated: bool, quality-score: uint})
(define-map product-custody uint principal)

;; Error codes
(define-constant ERR_ACCESS_DENIED (err u100))
(define-constant ERR_MANUFACTURER_NOT_AUTHORIZED (err u101))
(define-constant ERR_PRODUCT_NOT_FOUND (err u102))
(define-constant ERR_COMPANY_ALREADY_REGISTERED (err u103))
(define-constant ERR_INVALID_PARAMETERS (err u104))
(define-constant ERR_NOT_PRODUCT_HOLDER (err u105))
(define-constant ERR_INVALID_PRINCIPAL_ADDRESS (err u106))
(define-constant ERR_EMPTY_STRING_VALUE (err u107))
(define-constant ERR_INVALID_SCORE (err u108))

;; Constants
(define-constant ZERO_PRINCIPAL 'SP000000000000000000002Q6VF78)
(define-constant MAX_QUALITY_SCORE u1000)

;; Contract supervisor
(define-data-var supply-chain-supervisor principal tx-sender)

;; Supervisor functions
(define-public (change-supervisor (new-supervisor principal))
  (begin
    (asserts! (is-eq tx-sender (var-get supply-chain-supervisor)) ERR_ACCESS_DENIED)
    (asserts! (not (is-eq new-supervisor ZERO_PRINCIPAL)) ERR_INVALID_PRINCIPAL_ADDRESS)
    (ok (var-set supply-chain-supervisor new-supervisor))))

;; Manufacturer authorization
(define-public (authorize-manufacturer (company-name (string-ascii 64)))
  (begin
    (asserts! (> (len company-name) u0) ERR_EMPTY_STRING_VALUE)
    (let ((existing-company (default-to {company-name: "", authorized: false} (map-get? manufacturer-registry tx-sender))))
      (asserts! (not (get authorized existing-company)) ERR_COMPANY_ALREADY_REGISTERED)
      (ok (map-set manufacturer-registry tx-sender {company-name: company-name, authorized: true})))))

(define-public (revoke-manufacturer-authorization)
  (let ((existing-company (default-to {company-name: "", authorized: false} (map-get? manufacturer-registry tx-sender))))
    (asserts! (get authorized existing-company) ERR_MANUFACTURER_NOT_AUTHORIZED)
    (ok (map-set manufacturer-registry tx-sender 
      {company-name: (get company-name existing-company), authorized: false}))))

;; Product certificate management
(define-public (issue-product-certificate 
    (distributor principal) 
    (product-id uint) 
    (brand (string-ascii 64)) 
    (description (string-ascii 256)) 
    (qr-code (string-utf8 256)))
  (begin
    (asserts! (or (is-eq tx-sender (var-get supply-chain-supervisor)) 
                 (is-some (map-get? manufacturer-registry tx-sender))) ERR_ACCESS_DENIED)
    (asserts! (is-none (nft-get-owner? product-certificate product-id)) ERR_COMPANY_ALREADY_REGISTERED)
    
    (asserts! (not (is-eq distributor ZERO_PRINCIPAL)) ERR_INVALID_PRINCIPAL_ADDRESS)
    (asserts! (> (len brand) u0) ERR_EMPTY_STRING_VALUE)
    (asserts! (> (len description) u0) ERR_EMPTY_STRING_VALUE)
    (asserts! (> (len qr-code) u0) ERR_EMPTY_STRING_VALUE)
    
    (try! (nft-mint? product-certificate product-id distributor))
    (map-set product-info product-id {brand: brand, description: description, qr-code: qr-code})
    (map-set product-custody product-id distributor)
    (ok product-id)))

(define-public (transfer-product-custody (product-id uint) (new-holder principal))
  (begin
    (asserts! (is-eq tx-sender (unwrap! (nft-get-owner? product-certificate product-id) ERR_PRODUCT_NOT_FOUND)) ERR_NOT_PRODUCT_HOLDER)
    (asserts! (not (is-eq new-holder ZERO_PRINCIPAL)) ERR_INVALID_PRINCIPAL_ADDRESS)
    (try! (nft-transfer? product-certificate product-id tx-sender new-holder))
    (map-set product-custody product-id new-holder)
    (ok true)))

;; Quality inspection system
(define-public (set-quality-validation (product-id uint) (quality-score uint) (validated bool))
  (begin
    (asserts! (is-some (map-get? manufacturer-registry tx-sender)) ERR_MANUFACTURER_NOT_AUTHORIZED)
    (asserts! (is-some (nft-get-owner? product-certificate product-id)) ERR_PRODUCT_NOT_FOUND)
    (asserts! (&lt;= quality-score MAX_QUALITY_SCORE) ERR_INVALID_SCORE)
    (ok (map-set inspector-product-validation {inspector-id: tx-sender, product-id: product-id} 
                {validated: validated, quality-score: quality-score}))))

;; Specification validation helpers
(define-private (validate-spec (spec {component: (string-ascii 32), specification: (string-ascii 64)}))
  (and (> (len (get component spec)) u0) (> (len (get specification spec)) u0)))

(define-private (validate-specifications (specs (list 20 {component: (string-ascii 32), specification: (string-ascii 64)})))
  (let ((specs-len (len specs)))
    (and 
      (> specs-len u0)
      (is-eq specs-len (len (filter validate-spec specs))))))

;; Product specifications
(define-public (set-product-specifications (product-id uint) (specifications (list 20 {component: (string-ascii 32), specification: (string-ascii 64)})))
  (begin
    (asserts! (is-eq tx-sender (var-get supply-chain-supervisor)) ERR_ACCESS_DENIED)
    (asserts! (is-some (nft-get-owner? product-certificate product-id)) ERR_PRODUCT_NOT_FOUND)
    (asserts! (validate-specifications specifications) ERR_INVALID_SCORE)
    (ok (map-set product-specs product-id specifications))))

;; Query functions
(define-read-only (get-product-info (product-id uint))
  (map-get? product-info product-id))

(define-read-only (get-product-specifications (product-id uint))
  (map-get? product-specs product-id))

(define-read-only (get-quality-validation (inspector-id principal) (product-id uint))
  (map-get? inspector-product-validation {inspector-id: inspector-id, product-id: product-id}))

(define-read-only (get-manufacturer-info (manufacturer-id principal))
  (map-get? manufacturer-registry manufacturer-id))

(define-read-only (get-product-holder (product-id uint))
  (nft-get-owner? product-certificate product-id))

(define-read-only (is-manufacturer-authorized (manufacturer-id principal))
  (match (map-get? manufacturer-registry manufacturer-id)
    company-data (get authorized company-data)
    false))
