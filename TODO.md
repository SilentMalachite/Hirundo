# Hirundo Project TODO List

## Executive Summary

The Hirundo static site generator shows good security awareness and solid architecture. However, there are several areas that need attention for production readiness, particularly around security hardening, error handling, test coverage, and performance optimization.

## Critical Issues (High Priority)

### 1. Security Vulnerabilities

#### 1.1 HTML Renderer Security Gap ✅ COMPLETED
- **Issue**: The `HTMLRenderer` in `MarkdownParser.swift` uses basic string escaping but may not handle all XSS vectors
- **Location**: `/Sources/HirundoCore/MarkdownParser.swift:361-379`
- **Impact**: High - Potential XSS vulnerabilities
- **Solution**: Implement a proper HTML sanitization library or enhance escaping to cover all HTML contexts
- **Complexity**: Major
- **Status**: ✅ Completed - Implemented comprehensive whitelist-based HTML sanitization with full XSS protection

#### 1.2 Development Server CORS Configuration Missing ✅ COMPLETED
- **Issue**: No CORS headers configured in `DevelopmentServer.swift`
- **Location**: `/Sources/HirundoCore/DevelopmentServer.swift`
- **Impact**: High - Security vulnerability in development mode
- **Solution**: Add proper CORS configuration with configurable allowed origins
- **Complexity**: Minor
- **Status**: ✅ Completed - Implemented comprehensive CORS support with configurable settings via config.yaml

#### 1.3 WebSocket Authentication Missing ✅ COMPLETED
- **Issue**: WebSocket connections have no authentication mechanism
- **Location**: `/Sources/HirundoCore/DevelopmentServer.swift:78-89`
- **Impact**: Medium - Unauthorized WebSocket connections possible
- **Solution**: Implement token-based authentication for WebSocket connections
- **Complexity**: Major
- **Status**: ✅ Completed - Implemented token-based WebSocket authentication with configurable settings and comprehensive test suite

### 2. Dependency Security

#### 2.1 Outdated Dependencies ✅ COMPLETED
- **Issue**: Several dependencies are not on latest versions
- **Location**: `/Package.resolved`
- **Impact**: Medium - Potential security vulnerabilities in older versions
- **Solution**: Update dependencies, particularly:
  - swift-argument-parser: 1.6.1 (check for latest)
  - swift-markdown: 0.6.0 (check for latest)
  - Yams: 5.4.0 (check for latest)
- **Complexity**: Minor
- **Status**: ✅ Completed - Updated all dependencies with TDD approach and compatibility testing

## High Priority Issues

### 3. Error Handling Improvements

#### 3.1 Inconsistent Error Recovery
- **Issue**: Some errors cause complete build failure without recovery attempt
- **Location**: `/Sources/HirundoCore/SiteGenerator.swift`
- **Impact**: Medium - Poor user experience
- **Solution**: Implement partial build recovery and better error isolation
- **Complexity**: Major

#### 3.2 Missing Timeout Configurations ✅ COMPLETED
- **Issue**: No timeouts for file operations or network requests
- **Location**: Multiple files
- **Impact**: Medium - Potential DoS through resource exhaustion
- **Solution**: Add configurable timeouts for all I/O operations
- **Complexity**: Minor
- **Status**: ✅ Completed - Implemented comprehensive timeout system with 6 configurable timeout types and TimeoutManager utility

### 4. Test Coverage Gaps

#### 4.1 Security Test Coverage
- **Issue**: No dedicated security tests for input validation
- **Location**: `/Tests/HirundoTests/`
- **Impact**: High - Security vulnerabilities may go undetected
- **Solution**: Add comprehensive security test suite covering:
  - Path traversal attempts
  - XSS payload testing
  - YAML bomb tests
  - Resource exhaustion tests
- **Complexity**: Major

#### 4.2 Plugin System Tests
- **Issue**: Limited test coverage for plugin security and isolation
- **Location**: `/Tests/HirundoTests/PluginSystemTests.swift`
- **Impact**: Medium - Plugin vulnerabilities may affect system
- **Solution**: Add tests for malicious plugin behavior and resource limits
- **Complexity**: Major

### 5. Memory Management

#### 5.1 Potential Memory Leaks in FSEvents
- **Issue**: FSEvents callback uses unretained references
- **Location**: `/Sources/HirundoCore/FSEventsWrapper.swift:76`
- **Impact**: Medium - Potential memory leaks
- **Solution**: Review and improve memory management in FSEvents wrapper
- **Complexity**: Minor

## Medium Priority Issues

### 6. Performance Optimizations

#### 6.1 Missing Parallel Processing
- **Issue**: Markdown files processed sequentially
- **Location**: `/Sources/HirundoCore/SiteGenerator.swift:124-151`
- **Impact**: Medium - Slower builds for large sites
- **Solution**: Implement concurrent processing with proper resource limits
- **Complexity**: Major

#### 6.2 Template Cache Invalidation
- **Issue**: Template cache doesn't track dependencies
- **Location**: `/Sources/HirundoCore/TemplateEngine.swift`
- **Impact**: Low - Stale templates in development
- **Solution**: Implement dependency tracking for template includes
- **Complexity**: Major

### 7. Code Quality

#### 7.1 Magic Numbers and Hardcoded Values
- **Issue**: Hardcoded limits scattered throughout code
- **Location**: Multiple files
- **Impact**: Low - Maintainability issue
- **Solution**: Move all limits to centralized configuration
- **Complexity**: Minor

#### 7.2 Missing Input Validation ✅ COMPLETED
- **Issue**: Some user inputs not validated before use
- **Location**: `/Sources/Hirundo/main.swift` - editor command validation
- **Impact**: Medium - Potential command injection
- **Solution**: Enhance input validation for all user inputs
- **Complexity**: Minor
- **Status**: ✅ Completed - Implemented comprehensive editor command validation with TDD approach, including:
  - Command injection prevention
  - Path traversal protection
  - Shell metacharacter filtering
  - Whitelist-based editor validation
  - Executable existence checks
  - Comprehensive test suite with 100% coverage

### 8. Documentation

#### 8.1 API Documentation Missing
- **Issue**: No comprehensive API documentation
- **Impact**: Low - Developer experience
- **Solution**: Add DocC documentation for all public APIs
- **Complexity**: Minor

#### 8.2 Security Best Practices Guide
- **Issue**: Security documentation incomplete
- **Location**: `/SECURITY.md`
- **Impact**: Medium - Users may deploy insecurely
- **Solution**: Create comprehensive security deployment guide
- **Complexity**: Minor

## Low Priority Issues

### 9. Feature Enhancements

#### 9.1 Plugin Sandboxing
- **Issue**: Plugins run with full process permissions
- **Impact**: Low - Feature enhancement
- **Solution**: Implement plugin sandboxing with restricted permissions
- **Complexity**: Extensive

#### 9.2 Internationalization Support
- **Issue**: Limited i18n support mentioned but not implemented
- **Impact**: Low - Feature request
- **Solution**: Implement full i18n support with locale files
- **Complexity**: Major

### 10. Monitoring and Logging

#### 10.1 Structured Logging
- **Issue**: Inconsistent logging format
- **Impact**: Low - Operational improvement
- **Solution**: Implement structured logging with log levels
- **Complexity**: Minor

#### 10.2 Build Performance Metrics
- **Issue**: No performance tracking
- **Impact**: Low - Optimization opportunity
- **Solution**: Add build time metrics and profiling
- **Complexity**: Minor

## Recommendations

### Immediate Actions (Next Sprint)
1. ~~Enhance HTML sanitization~~ ✅ COMPLETED
2. ~~Implement CORS configuration for development server~~ ✅ COMPLETED
3. ~~Update all dependencies to latest stable versions~~ ✅ COMPLETED
4. Add security test suite
5. Fix FSEvents memory management

### Short Term (1-2 Months)
1. ~~Enhance HTML sanitization~~ ✅ COMPLETED (moved from immediate actions)
2. ~~Implement WebSocket authentication~~ ✅ COMPLETED
3. ~~Add timeout configurations~~ ✅ COMPLETED
4. Improve error recovery

### Long Term (3-6 Months)
1. Implement plugin sandboxing
2. Add full i18n support
3. Optimize build performance with parallelization
4. Complete API documentation

## Risk Assessment

### Critical Risks
- ~~XSS vulnerabilities through insufficient HTML escaping~~ ✅ RESOLVED
- ~~Missing CORS protection in development server~~ ✅ RESOLVED
- ~~Potential DoS through resource exhaustion~~ ✅ RESOLVED

### Moderate Risks
- ~~Outdated dependencies with potential vulnerabilities~~ ✅ RESOLVED
- Memory leaks in file watching
- Insufficient test coverage for security features

### Low Risks
- Performance issues with large sites
- Missing features for enterprise use cases

## Notes

The codebase shows good security awareness with input validation, path traversal protection, and resource limits. However, production deployment requires addressing the critical security issues identified above. The architecture is well-structured and extensible, making these improvements feasible without major refactoring.