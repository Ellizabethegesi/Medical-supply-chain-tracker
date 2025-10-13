# 💊 Medical Supply Chain Tracker

A comprehensive Clarity smart contract for tracking medical supplies, vaccines, and medicines through the supply chain to ensure authenticity and maintain chain of custody.

## 🎯 Features

- **🏭 Product Registration**: Manufacturers can register medical products with batch numbers and expiration dates
- **🚚 Supply Chain Tracking**: Track products through distributors, pharmacies, and hospitals
- **✅ Authenticity Verification**: Regulators can verify product authenticity
- **🔍 Chain of Custody**: Complete history of product ownership and location
- **⚠️ Counterfeit Reporting**: Report and track counterfeit products
- **🚨 Product Recalls**: Manufacturers and regulators can initiate product recalls
- **⏰ Expiration Monitoring**: Automatic expiration date validation

## 👥 Roles

- **MANUFACTURER** (Role 1): Can register products and initiate recalls
- **DISTRIBUTOR** (Role 2): Can receive and transfer products
- **PHARMACY** (Role 3): Can receive products and report counterfeits
- **HOSPITAL** (Role 4): Can receive products and report counterfeits
- **REGULATOR** (Role 5): Can verify authenticity, set roles, and initiate recalls

## 🚀 Usage

### Setting Up Roles

```clarity
;; Contract owner sets user roles
(contract-call? .Medical-SupplyCT set-user-role 'SP1234... u1) ;; Set as manufacturer
(contract-call? .Medical-SupplyCT set-user-role 'SP5678... u2) ;; Set as distributor
```

### Registering Products

```clarity
;; Manufacturer registers a vaccine
(contract-call? .Medical-SupplyCT register-product 
  "COVID-19 Vaccine" 
  "BATCH-001" 
  u1640995200 ;; manufacture date
  u1672531200 ;; expiry date
  "Manufacturing Facility A")
```

### Transferring Products

```clarity
;; Transfer product through supply chain
(contract-call? .Medical-SupplyCT transfer-product 
  u1 ;; product-id
  'SP5678... ;; recipient
  "Distribution Center B"
  (some -20) ;; temperature in Celsius
  "Cold chain maintained")
```

### Verifying Authenticity

```clarity
;; Regulator verifies product authenticity
(contract-call? .Medical-SupplyCT verify-product-authenticity u1)
```

### Reporting Counterfeits

```clarity
;; Report counterfeit batch
(contract-call? .Medical-SupplyCT report-counterfeit "FAKE-BATCH-001")
```

### Product Recalls

```clarity
;; Recall a product
(contract-call? .Medical-SupplyCT recall-product u1 "Quality control issue detected")
```

## 📖 Read-Only Functions

### Get Product Information
```clarity
(contract-call? .Medical-SupplyCT get-product u1)
```

### Get Product History
```clarity
(contract-call? .Medical-SupplyCT get-product-history u1 u0) ;; Get specific history entry
(contract-call? .Medical-SupplyCT get-product-history-count u1) ;; Get history count
```

### Verify Chain of Custody
```clarity
(contract-call? .Medical-SupplyCT verify-chain-of-custody u1)
```

### Check Product Expiration
```clarity
(contract-call? .Medical-SupplyCT is-product-expired u1)
```

### Get Batch Authenticity
```clarity
(contract-call? .Medical-SupplyCT get-batch-authenticity "BATCH-001")
```

## 🔒 Error Codes

- `u100`: Not authorized
- `u101`: Product already exists
- `u102`: Product not found
- `u103`: Invalid owner
- `u104`: Expired product
- `u105`: Invalid role
- `u106`: Already verified

## 🏗️ Contract Architecture

The contract uses several data structures:

- **Products Map**: Stores core product information
- **Product History Map**: Tracks ownership transfers and location changes
- **Batch Authenticity Map**: Stores authenticity verification data
- **User Roles Map**: Manages user permissions
- **Sequence Counters**: Tracks history sequence numbers

## 🧪 Testing

Run the contract validation:
```bash
clarinet check
```

Run tests:
```bash
clarinet test
```

## 📝 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
