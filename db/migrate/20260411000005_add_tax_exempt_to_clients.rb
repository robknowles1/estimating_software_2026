# Migration 5 of 5 — Add tax_exempt boolean to clients.
# ADR-008 Decision 5: tax_exempt is read from the client at estimate creation and
# copied onto the estimate. The client record retains its own flag for future
# estimates (default: false — most clients are taxable).
class AddTaxExemptToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :tax_exempt, :boolean, null: false, default: false
  end
end
