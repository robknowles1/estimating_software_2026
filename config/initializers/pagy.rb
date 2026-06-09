# frozen_string_literal: true

# Pagy 43.x configuration.
#
# Migrated from the pagy 9.x API (which used `Pagy::DEFAULT[:x]` and the
# `pagy/extras/overflow` extra). In pagy 43.x:
#   * Global defaults live in `Pagy::OPTIONS`.
#   * Out-of-range page handling is built in. With `raise_range_error: true`
#     pagy raises `Pagy::RangeError` (the replacement for the old
#     `Pagy::OverflowError`) so the controller can redirect to the last valid
#     page. The raised error exposes `#pagy`, whose `#last` is the last page.
Pagy::OPTIONS[:limit]            = 20
Pagy::OPTIONS[:raise_range_error] = true
