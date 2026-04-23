// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Ensure data-turbo-confirm buttons always use native window.confirm so that
// Selenium's accept_confirm helper (which waits for a native browser dialog)
// can reliably intercept the dialog in all environments, including headless
// Chrome in CI.  Turbo 8 falls back to FormSubmission.confirmMethod by
// default, which also calls window.confirm(), but some headless Chrome
// versions dispatch the dialog before Capybara's find_modal starts polling
// when the call goes through the async Promise chain.  Setting this
// explicitly keeps the confirm call synchronous and on the window object,
// which Chrome's CDP dialog event fires against synchronously.
Turbo.config.forms.confirm = (message) => window.confirm(message)

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
