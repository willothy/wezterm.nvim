# Changelog

## [0.3.0](https://github.com/willothy/wezterm.nvim/compare/v0.2.1...v0.3.0) (2023-10-18)


### ⚠ BREAKING CHANGES

* rename `current_pane` to `get_current_pane`

### Features

* add `list_panes` and `list_clients` ([cbc9c72](https://github.com/willothy/wezterm.nvim/commit/cbc9c7257fdbf6a057b6b09da2c0bd5f168a5e80))
* add `zoom_pane` and `current_pane` functions ([cd852a9](https://github.com/willothy/wezterm.nvim/commit/cd852a96b29866b7a70b84c9d3e9b86ba80fff65))
* rename `current_pane` to `get_current_pane` ([961e8f8](https://github.com/willothy/wezterm.nvim/commit/961e8f8e4f24eaae89458805836331072df3b31d))


### Bug Fixes

* use provided pane-id in `zoom_pane` ([f8f2cfe](https://github.com/willothy/wezterm.nvim/commit/f8f2cfe8981c01306dce2f062972a0ef8b69e9d9))

## [0.2.1](https://github.com/willothy/wezterm.nvim/compare/v0.2.0...v0.2.1) (2023-10-15)


### Bug Fixes

* **docs:** docgen for `dir` enum in get_pane_direction ([d8290f3](https://github.com/willothy/wezterm.nvim/commit/d8290f37d47956641eb975c7c0f32c92d0cf9c98))
* ensure setup, don't run without executable ([e0e331a](https://github.com/willothy/wezterm.nvim/commit/e0e331afccff50c0707352c73b2bb59523cab79f))

## [0.2.0](https://github.com/willothy/wezterm.nvim/compare/v0.1.1...v0.2.0) (2023-10-15)


### Features

* `get_pane_direction` and `get_text` ([1fa2495](https://github.com/willothy/wezterm.nvim/commit/1fa2495fdb795c166be3480f3edde100cd469ad7))
* add `exec_sync` function for sync commands ([1fa2495](https://github.com/willothy/wezterm.nvim/commit/1fa2495fdb795c166be3480f3edde100cd469ad7))


### Bug Fixes

* **docs:** docgen for multi-return in exec_sync ([07ab4bd](https://github.com/willothy/wezterm.nvim/commit/07ab4bdf3592ffdaac2ac5b08e48a2a6867fd5bc))
* ensure setup when calling `exec` or `exec_sync` ([1fa2495](https://github.com/willothy/wezterm.nvim/commit/1fa2495fdb795c166be3480f3edde100cd469ad7))

## [0.1.1](https://github.com/willothy/wezterm.nvim/compare/v0.1.0...v0.1.1) (2023-10-15)


### Bug Fixes

* docgen for optional keys ([bd77470](https://github.com/willothy/wezterm.nvim/commit/bd774700bf897cf487c84de464b93bf32799502c))

## 0.1.0 (2023-10-15)


### Features

* add cwd and direction args to SplitOpts ([98f874b](https://github.com/willothy/wezterm.nvim/commit/98f874b03fd72e48d6ec3d1fdef1d4bb73e500a5)), closes [#3](https://github.com/willothy/wezterm.nvim/issues/3)
* set tab and window titles ([bb33f0b](https://github.com/willothy/wezterm.nvim/commit/bb33f0b5c0f37c17709245f8ea0cf0bdd38d5018))
* set user vars for current pane ([4a9d9b5](https://github.com/willothy/wezterm.nvim/commit/4a9d9b5c47b774de4177f30708bf9a4cda6b75bc))
* split panes ([33b4732](https://github.com/willothy/wezterm.nvim/commit/33b4732414a1776da5c5c0bf83836a3ec6292610))
* use vim.v.count ([4439ea2](https://github.com/willothy/wezterm.nvim/commit/4439ea2b4b1fe7dc2158281cdafb8dd53bb81f23))


### Bug Fixes

* remote dev path from require ([aae12a7](https://github.com/willothy/wezterm.nvim/commit/aae12a7f17348c8fb025b182fb39f759d205c18d))
* uservar command should be SetUserVar ([ef98919](https://github.com/willothy/wezterm.nvim/commit/ef98919ada84c13f64b00d9c0f48b47eb38312a3))


### Continuous Integration

* add release-please workflow ([2db01a0](https://github.com/willothy/wezterm.nvim/commit/2db01a05c69032adccc952477a91387d38de4714))
