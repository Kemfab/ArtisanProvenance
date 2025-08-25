;; ArtisanProvenance - Digital art authenticity and provenance tracking system
;; This contract enables artists to mint authenticated artworks with verifiable ownership history

(define-non-fungible-token artwork uint)

;; Data storage
(define-map artwork-metadata uint {name: (string-ascii 64), story: (string-ascii 256), image-url: (string-utf8 256)})
(define-map artwork-attributes uint (list 20 {trait: (string-ascii 32), characteristic: (string-ascii 64)}))
(define-map artist-registry principal {studio-name: (string-ascii 64), verified: bool})
(define-map gallery-artwork-approval {gallery-id: principal, artwork-id: uint} {approved: bool, rating: uint})
(define-map artwork-provenance uint principal)

;; Error codes
(define-constant ERR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERR_ARTIST_NOT_VERIFIED (err u101))
(define-constant ERR_ARTWORK_NOT_EXISTS (err u102))
(define-constant ERR_STUDIO_ALREADY_EXISTS (err u103))
(define-constant ERR_INVALID_INPUT (err u104))
(define-constant ERR_NOT_ARTWORK_OWNER (err u105))
(define-constant ERR_INVALID_ADDRESS (err u106))
(define-constant ERR_EMPTY_FIELD (err u107))
(define-constant ERR_INVALID_RATING (err u108))

;; Constants
(define-constant NULL_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MAX_GALLERY_RATING u1000)

;; Contract administrator
(define-data-var platform-admin principal tx-sender)

;; Administrative functions
(define-public (update-platform-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (not (is-eq new-admin NULL_ADDRESS)) ERR_INVALID_ADDRESS)
    (ok (var-set platform-admin new-admin))))

;; Artist verification
(define-public (register-artist-studio (studio-name (string-ascii 64)))
  (begin
    (asserts! (> (len studio-name) u0) ERR_EMPTY_FIELD)
    (let ((existing-studio (default-to {studio-name: "", verified: false} (map-get? artist-registry tx-sender))))
      (asserts! (not (get verified existing-studio)) ERR_STUDIO_ALREADY_EXISTS)
      (ok (map-set artist-registry tx-sender {studio-name: studio-name, verified: true})))))

(define-public (deactivate-artist-studio)
  (let ((existing-studio (default-to {studio-name: "", verified: false} (map-get? artist-registry tx-sender))))
    (asserts! (get verified existing-studio) ERR_ARTIST_NOT_VERIFIED)
    (ok (map-set artist-registry tx-sender 
      {studio-name: (get studio-name existing-studio), verified: false}))))

;; Artwork minting and transfer
(define-public (mint-artwork 
    (collector principal) 
    (artwork-id uint) 
    (name (string-ascii 64)) 
    (story (string-ascii 256)) 
    (image-url (string-utf8 256)))
  (begin
    (asserts! (or (is-eq tx-sender (var-get platform-admin)) 
                 (is-some (map-get? artist-registry tx-sender))) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (is-none (nft-get-owner? artwork artwork-id)) ERR_STUDIO_ALREADY_EXISTS)
    
    (asserts! (not (is-eq collector NULL_ADDRESS)) ERR_INVALID_ADDRESS)
    (asserts! (> (len name) u0) ERR_EMPTY_FIELD)
    (asserts! (> (len story) u0) ERR_EMPTY_FIELD)
    (asserts! (> (len image-url) u0) ERR_EMPTY_FIELD)
    
    (try! (nft-mint? artwork artwork-id collector))
    (map-set artwork-metadata artwork-id {name: name, story: story, image-url: image-url})
    (map-set artwork-provenance artwork-id collector)
    (ok artwork-id)))

(define-public (transfer-artwork (artwork-id uint) (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender (unwrap! (nft-get-owner? artwork artwork-id) ERR_ARTWORK_NOT_EXISTS)) ERR_NOT_ARTWORK_OWNER)
    (asserts! (not (is-eq new-collector NULL_ADDRESS)) ERR_INVALID_ADDRESS)
    (try! (nft-transfer? artwork artwork-id tx-sender new-collector))
    (map-set artwork-provenance artwork-id new-collector)
    (ok true)))

;; Gallery approval system
(define-public (set-gallery-approval (artwork-id uint) (rating uint) (approved bool))
  (begin
    (asserts! (is-some (map-get? artist-registry tx-sender)) ERR_ARTIST_NOT_VERIFIED)
    (asserts! (is-some (nft-get-owner? artwork artwork-id)) ERR_ARTWORK_NOT_EXISTS)
    (asserts! (<= rating MAX_GALLERY_RATING) ERR_INVALID_RATING)
    (ok (map-set gallery-artwork-approval {gallery-id: tx-sender, artwork-id: artwork-id} 
                {approved: approved, rating: rating}))))

;; Validation helpers
(define-private (validate-attribute (attr {trait: (string-ascii 32), characteristic: (string-ascii 64)}))
  (and (> (len (get trait attr)) u0) (> (len (get characteristic attr)) u0)))

(define-private (validate-attributes (attrs (list 20 {trait: (string-ascii 32), characteristic: (string-ascii 64)})))
  (let ((attrs-len (len attrs)))
    (and 
      (> attrs-len u0)
      (is-eq attrs-len (len (filter validate-attribute attrs))))))

;; Artwork attributes
(define-public (set-artwork-attributes (artwork-id uint) (attributes (list 20 {trait: (string-ascii 32), characteristic: (string-ascii 64)})))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (is-some (nft-get-owner? artwork artwork-id)) ERR_ARTWORK_NOT_EXISTS)
    (asserts! (validate-attributes attributes) ERR_INVALID_RATING)
    (ok (map-set artwork-attributes artwork-id attributes))))

;; Query functions
(define-read-only (get-artwork-metadata (artwork-id uint))
  (map-get? artwork-metadata artwork-id))

(define-read-only (get-artwork-attributes (artwork-id uint))
  (map-get? artwork-attributes artwork-id))

(define-read-only (get-gallery-approval (gallery-id principal) (artwork-id uint))
  (map-get? gallery-artwork-approval {gallery-id: gallery-id, artwork-id: artwork-id}))

(define-read-only (get-artist-studio (artist-id principal))
  (map-get? artist-registry artist-id))

(define-read-only (get-artwork-owner (artwork-id uint))
  (nft-get-owner? artwork artwork-id))

(define-read-only (is-artist-verified (artist-id principal))
  (match (map-get? artist-registry artist-id)
    studio-data (get verified studio-data)
    false))
