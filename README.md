# MediTrack Subscription
 
# MediTrack Subscription System

A decentralized subscription management system for healthcare providers built on Stacks blockchain, enabling secure and compliant access to patient records.

## Overview

MediTrack Subscription is a smart contract system that manages healthcare provider subscriptions with different access tiers, emergency override capabilities, and HIPAA-compliant access controls.

## Features

- **Tiered Subscription Model**
  - Basic tier for general practitioners
  - Specialist tier with enhanced access
  - Time-locked subscription periods

- **Access Control**
  - HIPAA-compliant access management
  - Emergency access override
  - Subscription status verification

- **Security**
  - Blockchain-based authentication
  - Automated expiration handling
  - Principal-based access control

## Smart Contract Functions

### Public Functions

- `subscribe(tier)`: Subscribe to either basic or specialist tier
- `enable-emergency-access()`: Activate emergency access override
- `get-subscription(provider)`: Get subscription details
- `is-active-subscriber(provider)`: Check subscription status

## Testing

The project includes comprehensive test coverage using Clarinet and Vitest:

```bash
npm test
