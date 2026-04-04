# ADR-004: Authentication — has_secure_password with Admin-Only User Creation

**Status:** accepted
**Date:** 2026-04-01
**Deciders:** architect-agent

---

## Context

The application requires authentication: no public access, all routes protected. The spec proposes `has_secure_password` (bcrypt) with session-based auth. An open question (OQ-10) asks whether users can self-register or must be invited by an admin.

The shop is a single-location millwork business. The user population is small (2–5 estimators) and stable. There is no external user base, no customer-facing login, and no OAuth provider relationship to leverage. The spec's non-goals explicitly exclude role-based access control for MVP.

## Decision

Use `has_secure_password` with bcrypt and Rails session-based authentication. No self-registration. Users are created by seeding or by a logged-in user navigating to an admin-only `/users/new` route. There is no "admin" role distinction in MVP — any logged-in user can create other users. A simple invite-by-creation model is sufficient: create the account, tell the new user their temporary password, they log in and change it.

Do not use Devise, Rodauth, or an OAuth provider for MVP.

## Rationale

**has_secure_password is sufficient and appropriate.** The threat model for this application is: prevent unauthorized external access to estimating data. A small internal team of known users with bcrypt-hashed passwords and a server-side session is a well-understood, auditable security boundary. It is not a public SaaS product where credential stuffing, account takeover, or self-registration spam are relevant concerns.

**Self-registration is rejected.** The shop does not want unauthorized people accessing its pricing data. Self-registration would require an invitation token system or email verification to prevent unwanted signups, adding complexity. Since accounts are created by existing staff, admin-creates-account is simpler and more appropriate.

**Devise is not added.** Devise is a well-maintained gem, but it is a substantial dependency that generates significant amounts of views, routes, and configuration. For a 2–5 user internal tool, it provides no meaningful benefit over a hand-rolled `SessionsController` and `has_secure_password`. Devise also tends to make simple auth harder to understand and modify because of its module/concern architecture.

**Rodauth is not added.** Rodauth is the correct choice for a security-critical, high-user-count application. For this use case, it is architectural overkill.

**OAuth is not added.** There is no identity provider relationship to leverage (the shop does not use Google Workspace, Microsoft 365, or similar in a way that would make OAuth natural). Adding OAuth for a 5-person internal tool creates a dependency on an external service for basic access.

**Password reset:** Rails 8 ships with `ActionMailer` and the app has `ApplicationMailer` scaffolded. A minimal password reset via emailed token is achievable post-MVP with minimal additional code. For MVP, a logged-in user can reset another user's password directly.

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| has_secure_password (chosen) | Built into Rails, no extra gems, simple, auditable | No built-in password reset email, no session management extras | N/A — chosen |
| Devise | Feature-rich, well-documented, large community | Heavy dependency, generates hard-to-modify boilerplate, overkill for 5 users | Unjustified complexity for use case |
| Rodauth | Extremely secure, modular, Rails-idiomatic | Steeper learning curve, more configuration overhead | Overkill for internal tool with 2-5 users |
| OAuth (Google/Microsoft) | No password management, familiar UX | External dependency, requires provider account/app setup, adds latency | No existing provider relationship; complexity not justified |

## Consequences

### Positive
- Minimal code surface: `SessionsController` (create/destroy), `User` model with `has_secure_password`, a `before_action :require_login` concern on `ApplicationController`.
- No new gems required beyond uncommenting `bcrypt` in the Gemfile.
- Session stored server-side in the database via Rails' default cookie-based session (encrypted, signed). No separate session store configuration needed for MVP.
- Fully auditable: all auth logic is in the app, readable by any Rails developer.

### Negative
- No built-in password reset by email for MVP. Must be added manually if needed.
- No "remember me" / persistent sessions without additional code.
- No account lockout after failed attempts (brute-force protection). Acceptable for an internal tool on a private network; worth adding if the app is exposed to the public internet.

### Risks
- **Risk:** The app is deployed publicly (via Kamal) with no additional network-level access control. A stolen session cookie would grant access. Mitigation: ensure `config.force_ssl = true` in production so the session cookie is only sent over HTTPS; set `config.session_store :cookie_store, key: '_estimating_session', secure: Rails.env.production?`.
- **Risk:** bcrypt gem is currently commented out in the Gemfile. If authentication is built before this is uncommented, `has_secure_password` will fail silently or raise at runtime. Mitigation: uncommenting bcrypt is the first task in the authentication story. Make it a prerequisite in the build order.
- **Risk:** All logged-in users can create new users. A disgruntled employee could create accounts. Mitigation: for a 2-5 person shop this is an acceptable trust model; flag for post-MVP role addition if needed.

## Implementation Notes

**Gemfile change required (Day 1 blocker):**
```ruby
gem "bcrypt", "~> 3.1.7"
```

**User model:**
```ruby
class User < ApplicationRecord
  has_secure_password
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  normalizes :email, with: ->(e) { e.strip.downcase }
end
```

**ApplicationController concern:**
```ruby
module Authentication
  extend ActiveSupport::Concern
  included do
    before_action :require_login
    helper_method :current_user, :logged_in?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in? = current_user.present?

  def require_login
    redirect_to login_path, alert: "Please log in." unless logged_in?
  end
end
```

**Routes:**
```ruby
get  "login",  to: "sessions#new",     as: :login
post "login",  to: "sessions#create"
delete "logout", to: "sessions#destroy", as: :logout
resources :users, only: [:index, :new, :create, :edit, :update]
```

**SessionsController:**
- `#create`: find user by email, call `authenticate(password)`, set `session[:user_id]`, redirect to root.
- `#destroy`: reset session, redirect to login.
- Do not rescue `ActiveRecord::RecordNotFound` separately from a failed authenticate — always show the same generic error message to prevent user enumeration.

**User management:** `UsersController` requires login. For MVP, any logged-in user can create/edit users. Password reset is a manual admin action (edit the user record). Do not expose destroy — deactivating users is a post-MVP concern.

**Session security in production:**
```ruby
# config/environments/production.rb
config.force_ssl = true
```
Kamal handles TLS termination; ensure the Kamal config includes an SSL certificate.
