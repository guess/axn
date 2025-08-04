# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2025-08-04

### Changed
- **BREAKING**: Validation functions now receive `(changeset, ctx)` instead of `(changeset)`
- Validation functions can now pattern match on context fields like action name and user data
- Enhanced validation capabilities with access to full action context

### Added
- Pattern matching support in validation functions for context-aware validation
- Access to `ctx.action`, `ctx.assigns`, and other context fields in validation functions
- Advanced validation examples in documentation showing multi-action pattern matching
- New tests demonstrating pattern matching on action name, user role, and context fields

### Migration Guide
- Update validation function signatures from `validate_fn(changeset)` to `validate_fn(changeset, ctx)`
- Update function references from `&function/1` to `&function/2`
- Optionally leverage pattern matching on `ctx.action` for different validation rules per action

## [0.1.0] - 2025-08-04

### Added
- Initial release of Axn - Action DSL for Phoenix
- Core DSL with `action` and `step` macros
- `Axn.Context` struct with helper functions for managing action state
- Built-in `:cast_validate_params` step for parameter validation
- Automatic telemetry integration with configurable metadata
- Support for external steps from other modules
- Unified API that works with both Phoenix Controllers and LiveViews
- Comprehensive error handling with consistent error formats
- Complete test suite with 30+ tests
- Documentation with guides for testing, telemetry, and advanced usage

### Features
- **Actions**: Named units of work that execute steps in sequence
- **Steps**: Pure functions that take context and return continuation or halt
- **Context Flow**: Phoenix-style assigns and params flow through step pipeline
- **Parameter Validation**: Schema-based validation with optional custom validation functions
- **Authorization Patterns**: Simple, testable authorization step patterns
- **Telemetry**: Automatic span wrapping with safe metadata extraction
- **Phoenix Integration**: Seamless integration with both Controllers and LiveViews
- **Testing Support**: Helper functions and patterns for easy testing

[Unreleased]: https://github.com/guess/axn/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/guess/axn/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/guess/axn/commits/v0.1.0