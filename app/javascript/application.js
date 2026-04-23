// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Mark the HTML element once all JS modules have initialised.  System specs
// can wait on this attribute to ensure Turbo event listeners are registered
// before they click confirm-protected buttons.
//
// We reset the flag at the start of every Turbo navigation and restore it only
// after turbo:load completes.  This prevents a false-positive from Turbo's
// page cache: a cached snapshot already has data-js-ready="true" but Turbo's
// own event listeners (including the data-turbo-confirm handler) have not yet
// re-registered for the new page.  Without the reset, wait_for_js() in system
// specs can pass on the stale cached value and accept_confirm then races
// against a confirm() dialog that never fires.
document.addEventListener("turbo:visit", function () {
  document.documentElement.dataset.jsReady = "false"
})

document.addEventListener("turbo:load", function () {
  document.documentElement.dataset.jsReady = "true"
})

// Set immediately for the very first (non-Turbo) page load so that specs
// which do not trigger any Turbo navigation also see the flag.
document.documentElement.dataset.jsReady = "true"
