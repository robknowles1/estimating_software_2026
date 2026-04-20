// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Mark the HTML element once all JS modules have initialised.  System specs
// can wait on this attribute to ensure Turbo event listeners are registered
// before they click confirm-protected buttons.
document.documentElement.dataset.jsReady = "true"
