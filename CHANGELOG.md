# Changelog

## [1.7.3](https://github.com/datapointchris/font/compare/v1.7.2...v1.7.3) (2026-03-23)


### Bug Fixes

* remove dead normalization call from sync merge ([62eddd6](https://github.com/datapointchris/font/commit/62eddd6346345eacac97aa8f91e1324f522be8d8))

## [1.7.2](https://github.com/datapointchris/font/compare/v1.7.1...v1.7.2) (2026-03-23)


### Bug Fixes

* support macOS in font install --check ([8eacee5](https://github.com/datapointchris/font/commit/8eacee5e2b72ea19d2388f3d902f9dbbe4a16e59))

## [1.7.1](https://github.com/datapointchris/font/compare/v1.7.0...v1.7.1) (2026-03-23)


### Bug Fixes

* update history normalization for new spaced font names ([ab64bd6](https://github.com/datapointchris/font/commit/ab64bd63d283ed8be7b31583fac25a9ab1616e26))

## [1.7.0](https://github.com/datapointchris/font/compare/v1.6.6...v1.7.0) (2026-03-23)


### Features

* add font install command and curation script ([0360b23](https://github.com/datapointchris/font/commit/0360b2317cbe05a20b6fe95901e832da420c8f66))

## [1.6.6](https://github.com/datapointchris/font/compare/v1.6.5...v1.6.6) (2026-03-23)


### Bug Fixes

* filter orphan base fonts and normalize lowercase history entries ([ec70cbb](https://github.com/datapointchris/font/commit/ec70cbbef736cf3a7cba38058cea4cec41c87bb4))

## [1.6.5](https://github.com/datapointchris/font/compare/v1.6.4...v1.6.5) (2026-03-21)


### Bug Fixes

* validate font apply and remove CommitMono entries ([cbfbb24](https://github.com/datapointchris/font/commit/cbfbb24c001097b7a6a05213b3a6b98aea82baee))

## [1.6.4](https://github.com/datapointchris/font/compare/v1.6.3...v1.6.4) (2026-02-12)


### Bug Fixes

* flip Nimbus Mono PS normalization to match fc-list output ([ef5d3d4](https://github.com/datapointchris/font/commit/ef5d3d4d04a7a73dbed4d6db9a31042723d591e3))

## [1.6.3](https://github.com/datapointchris/font/compare/v1.6.2...v1.6.3) (2026-02-11)


### Bug Fixes

* normalize old font and machine names in history on read and sync ([60835c5](https://github.com/datapointchris/font/commit/60835c5e37cba211b8833630f3e84ea5f340f9ca))
* rename Comic Mono and Fira Code to canonical names in font-info ([640a918](https://github.com/datapointchris/font/commit/640a918a78af7bc8f3b6b8a35c5585606e8349a7))

## [1.6.2](https://github.com/datapointchris/font/compare/v1.6.1...v1.6.2) (2026-02-11)


### Bug Fixes

* add parentheses to jq score arithmetic for jq 1.7 compatibility ([dfcfa36](https://github.com/datapointchris/font/commit/dfcfa362e388ba2821af7a25244229e57a08c1a8))

## [1.6.1](https://github.com/datapointchris/font/compare/v1.6.0...v1.6.1) (2026-02-11)


### Bug Fixes

* apply Windows Terminal font changes to all profiles, not just defaults ([81ce483](https://github.com/datapointchris/font/commit/81ce48391585dd16a10dc590286af0855dfbc467)), closes [#11](https://github.com/datapointchris/font/issues/11)

## [1.6.0](https://github.com/datapointchris/font/compare/v1.5.2...v1.6.0) (2026-01-26)


### Features

* add terminal config initialization on module load ([c510fe7](https://github.com/datapointchris/font/commit/c510fe7a3c88e9f9a9a18d9c98b76063c93fce83))


### Bug Fixes

* use uname -n instead of hostname -s in get_machine_id ([f2c0ff1](https://github.com/datapointchris/font/commit/f2c0ff13920332465b88bc8e85ed83311d3d6c05))
* **waybar:** use direct font-family instead of CSS custom properties ([2048645](https://github.com/datapointchris/font/commit/20486456e7be5b404b9db98b16e04a992abff85a))

## [1.5.2](https://github.com/datapointchris/font/compare/v1.5.1...v1.5.2) (2026-01-22)


### Reverts

* simplify history sorting back to lexicographic comparison ([576aa2e](https://github.com/datapointchris/font/commit/576aa2e1121cb51703671e2ca71f3d853ae5e43b))

## [1.5.1](https://github.com/datapointchris/font/compare/v1.5.0...v1.5.1) (2026-01-22)


### Bug Fixes

* normalize timezone formats before sorting history entries ([1d7a89a](https://github.com/datapointchris/font/commit/1d7a89a17086a21ea5dd42cd0ce24a1d7123402a))

## [1.5.0](https://github.com/datapointchris/font/compare/v1.4.1...v1.5.0) (2026-01-18)


### Features

* add 'font last' command to toggle between recent fonts ([d0a6561](https://github.com/datapointchris/font/commit/d0a6561d35975971ac247892cf06c28003e92a3c))

## [1.4.2](https://github.com/datapointchris/font/compare/v1.4.1...v1.4.2) (2026-01-17)

### Code Refactoring

* update all terminal configs simultaneously for font changes ([adcbed1](https://github.com/datapointchris/font/commit/adcbed1))

## [1.4.1](https://github.com/datapointchris/font/compare/v1.4.0...v1.4.1) (2026-01-17)

### Bug Fixes

* sort history entries by timestamp instead of lexicographically ([17ef048](https://github.com/datapointchris/font/commit/17ef048cf01393f94f9bedb3c3c7ace4b818f352))

## [1.4.0](https://github.com/datapointchris/font/compare/v1.3.0...v1.4.0) (2026-01-17)

### Features

* add visual enhancements to font rank output ([fdc4d09](https://github.com/datapointchris/font/commit/fdc4d09448e6e1840f3fbb237a58549dea1bb7a8))

## [1.3.0](https://github.com/datapointchris/font/compare/v1.2.0...v1.3.0) (2026-01-17)

### Features

* add info command and enhance history display ([c9f59f6](https://github.com/datapointchris/font/commit/c9f59f6a7aae957c3fd098988a3786851dc13c2e))

## [1.2.0](https://github.com/datapointchris/font/compare/v1.1.1...v1.2.0) (2026-01-17)

### Features

* display notes in font current command ([f6d2726](https://github.com/datapointchris/font/commit/f6d272629e8e1449f1feaa2ea1e33d011c8419e5))

## [1.1.1](https://github.com/datapointchris/font/compare/v1.1.0...v1.1.1) (2026-01-15)

### Bug Fixes

* exclude rejected fonts from rankings ([1e1cdfe](https://github.com/datapointchris/font/commit/1e1cdfe6cbfe58def07be9ea98b33f3823dc4263))

## [1.1.0](https://github.com/datapointchris/font/compare/v1.0.0...v1.1.0) (2026-01-09)

### Features

* upgrade only pulls tagged releases, not unreleased code ([0ca0092](https://github.com/datapointchris/font/commit/0ca009237da3d87a6188a58fa3cdf2ea8c4f2f6b))

### Bug Fixes

* resolve shellcheck warnings ([0c302bd](https://github.com/datapointchris/font/commit/0c302bd35f4c2b4c70415117c24df8b733e5a54b))
* use correct release-please action ([9bb847a](https://github.com/datapointchris/font/commit/9bb847a30dc571dc11236f22141582f52170aa23))
