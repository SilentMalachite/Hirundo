# WebSocket Authentication Implementation

## Overview

This document describes the implementation of secure token-based authentication for WebSocket connections in the Hirundo development server. The implementation follows Test-Driven Development (TDD) practices and addresses the security vulnerability identified in TODO item 1.3.

## Problem Statement

**Issue**: WebSocket connections in the development server had no authentication mechanism, allowing unauthorized connections.

**Location**: `/Sources/HirundoCore/DevelopmentServer.swift`

**Impact**: Medium - Unauthorized WebSocket connections possible

## Solution

A token-based authentication system has been implemented with the following components:

### 1. Configuration Model

New `WebSocketAuthConfig` struct in `/Sources/HirundoCore/Models/Config.swift`:

```swift
public struct WebSocketAuthConfig: Codable {
    public let enabled: Bool
    public let tokenExpirationMinutes: Int
    public let maxActiveTokens: Int
    
    public init(
        enabled: Bool = true,
        tokenExpirationMinutes: Int = 60,
        maxActiveTokens: Int = 100
    )
}
```

### 2. Token Management

Implemented secure token generation and validation:

- **Token Generation**: 32-character alphanumeric tokens using cryptographically secure random generation
- **Token Storage**: In-memory storage with expiration tracking
- **Token Validation**: Validates token existence and expiration
- **Token Cleanup**: Automatic cleanup of expired tokens and enforcement of maximum token limits

### 3. Authentication Endpoint

Added `/auth-token` endpoint that:
- Generates a new authentication token
- Returns token with expiration information
- Supports CORS headers for cross-origin requests

### 4. WebSocket Authentication Flow

The authentication flow works as follows:

1. Client fetches an authentication token from `/auth-token`
2. Client establishes WebSocket connection to `/livereload`
3. Server sends authentication challenge
4. Client responds with authentication token
5. Server validates token and sends success/error response
6. Only authenticated connections receive live reload notifications

### 5. Enhanced Client Script

Updated the live reload client script to:
- Fetch authentication tokens automatically
- Handle authentication challenges
- Manage authentication state
- Provide error logging and handling

## Configuration

WebSocket authentication can be configured in `config.yaml`:

```yaml
server:
  port: 8080
  liveReload: true
  websocketAuth:
    enabled: true              # Enable/disable authentication (default: true)
    tokenExpirationMinutes: 60 # Token lifetime in minutes (default: 60)
    maxActiveTokens: 100       # Maximum concurrent tokens (default: 100)
```

## Security Features

### Token Security
- 32-character minimum length for strong entropy
- Alphanumeric characters only to prevent injection attacks
- No sensitive information embedded in tokens
- Cryptographically secure random generation

### Access Control
- Token-based authentication prevents unauthorized connections
- Configurable token expiration prevents long-term token abuse
- Maximum token limits prevent resource exhaustion
- Automatic cleanup of expired tokens

### Error Handling
- Graceful handling of authentication failures
- Proper error messages for debugging
- Connection termination on authentication failure

## Testing

Comprehensive test suite implemented following TDD principles:

### Test Coverage
- Token generation and uniqueness
- Token validation logic
- Token expiration handling
- WebSocket connection authentication
- Authentication endpoint functionality
- Security properties validation

### Test File
All tests are located in `/Tests/HirundoTests/WebSocketAuthenticationTests.swift` with 10 test cases covering:
- Token generation and security properties
- Authentication success/failure scenarios
- Endpoint functionality
- Edge cases and error conditions

## API Reference

### DevelopmentServer Methods

```swift
// Generate a new authentication token
public func generateAuthToken() -> String

// Validate an authentication token
public func validateAuthToken(_ token: String) -> Bool

// Authenticate a WebSocket connection
public func authenticateWebSocketConnection(_ session: Any, token: String?) -> Bool

// Get the auth token endpoint path
public func getAuthTokenEndpoint() -> String

// Expire a token (for testing)
public func expireAuthToken(_ token: String)
```

### HTTP Endpoints

#### GET /auth-token
Returns a JSON response with authentication token:

```json
{
  "token": "abc123...",
  "expiresIn": 60,
  "endpoint": "/livereload"
}
```

#### WebSocket /livereload
WebSocket endpoint for live reload functionality with authentication.

**Authentication Messages:**

Server challenge:
```json
{
  "type": "auth_required",
  "message": "Please provide authentication token"
}
```

Client authentication:
```json
{
  "type": "auth",
  "token": "abc123..."
}
```

Server response (success):
```json
{
  "type": "auth_success",
  "message": "Authentication successful"
}
```

Server response (error):
```json
{
  "type": "auth_error",
  "message": "Invalid or expired token"
}
```

## Implementation Notes

### Thread Safety
- All token operations are protected by concurrent dispatch queues
- Atomic operations for token storage and retrieval
- Safe cleanup of expired tokens

### Memory Management
- WeakWebSocketSession wrapper prevents memory leaks
- Automatic cleanup of dead WebSocket sessions
- Bounded token storage with configurable limits

### Backward Compatibility
- Authentication can be disabled via configuration
- Fallback handling for non-JSON WebSocket messages
- Graceful degradation for unsupported clients

## Files Modified

1. `/Sources/HirundoCore/Models/Config.swift` - Added WebSocketAuthConfig
2. `/Sources/HirundoCore/DevelopmentServer.swift` - Implemented authentication system
3. `/Tests/HirundoTests/WebSocketAuthenticationTests.swift` - Created test suite

## Security Considerations

This implementation provides:
- **Authentication**: Verified token-based access control
- **Authorization**: Only valid token holders can establish connections
- **Non-repudiation**: Token generation and validation are logged
- **Integrity**: Secure token generation prevents forgery
- **Availability**: Rate limiting through maximum token limits

The system is designed for development environments and provides reasonable security for local development scenarios while maintaining usability and performance.