# Meeting Notes — 2026-05-22 User Feedback Session

Participants: Rob (developer), Blake (estimator, TrimArt)

---

## Confirmed / Already Built

- **CSV import for line items** — Blake liked it. Needs minor refinement on which line items to skip (e.g. "Finished Schedule" rows that aren't needed).
- **Find-or-create on line items** — Adding a new product inline also creates it in the price book. Confirmed working.
- **Material sets** — Concept explained and demoed. Blake understood it and approved the direction.
- **Price book per estimate** — Equivalent to Blake's "material cost tab" in the Excel sheet.

---

## Changes / Clarifications

### 1. Date Fields on Estimate
- Replace current "start date / end date" with:
  - **Bid Due Date**
  - **Job Start Date**

### 2. Material Short Names / Aliases (HIGH PRIORITY)
- Architects name materials per job using codes like `PL1`, `SS5`, etc.
- These are **job-specific** — they change every project.
- The price book needs a field for a **customizable short name / alias** per material.
- When `PL1` appears in an imported CSV line item, the system should map it to the correct material via this alias and **auto-populate all defaults** for that line item.
- This is the single biggest time-saver: Blake went from a full-day estimate to **15 minutes** in Excel by doing this with auto-population logic.

### 3. Auto-population of Line Item Defaults
- When a product is matched from the catalog (by alias or name), all default fields should populate automatically.
- Fields that should auto-populate: material, labor, markup, overhead, profit, unit, etc.
- User should only have to touch the things that are truly custom per job.
- Fields that DON'T auto-populate (or need review) should be visually flagged.

### 4. Materials Library — Search & Pagination
- As the library grows it will need:
  - Live search / filter as you type
  - Pagination (~20 per page)
- Currently no search on the materials index.

---

## New Features Requested

### 5. Asana API Integration for Material Prices
- TrimArt tracks material prices (with vendor info and date last updated) in Asana.
- **Want**: a background sync job (daily or hourly) that pulls material data from Asana into the app.
- Asana = source of truth. App pulls from it, not the other way.
- **Future/v2**: When a material price is older than a threshold (e.g. 1 week), auto-compile a list and email the vendor asking for updated pricing. CC the purchaser so replies go to them.
- Rob needs Blake's Asana API key to start this.

### 6. Proposal / Bid Letter Wizard (HIGH PRIORITY)
This is the primary output of an estimate. Currently Blake hand-types a Word doc every time.

**Proposal structure** (based on the `PROPOSAL TEMPLATE - TrimArt Proposal - 3.30.2026.dotx`):

| Section | Always present? | Notes |
|---|---|---|
| Header / Opening letter | Yes | Date, salutation, job name, plan date, addendum list, total amount in $ and words |
| Specification Sections | Optional (toggle on/off) | List of spec numbers (e.g. `064023 - Interior Architectural Woodwork`) |
| Specific Inclusions | Yes | Room-by-room breakdown. Each room: brief bullet list of what was included + optional photos |
| Design Clarifications | Yes | Standard list; user can add/remove items |
| Alternates | Conditional | Only shown if alternates exist in the estimate. Not rolled into base bid total |
| Specific Exclusions | Yes | Standard list; user can add/remove |
| Signature | Yes | Auto-populated from logged-in user (name, phone, email) |

**Wizard flow:**
1. Opening — choose/confirm client contact, job name, plan date, addendum list, total
2. Specifications — toggle on/off; if on, enter spec numbers
3. Specific Inclusions — rooms auto-populated from CSV import; user adds bullet points + optional photo per room
4. Design Clarifications — pre-populated standard list; user edits
5. Alternates — auto-detected if alternates in estimate; user confirms pricing
6. Exclusions — pre-populated standard list; user edits
7. Review & Export — preview, download PDF, and/or send email

**Output options:**
- Download as PDF
- Send email directly (auto-drafted with estimate PDF attached)
- Save to Google Drive (future)

**Residential vs Commercial:**
- There is a separate simpler residential bid letter template (`Residential Bid Letter - TrimArt Proposal - 3.9.2026.dotx`)
- Residential format: description of materials/labor, room-by-room pricing summary, payment terms, alternates, ideas section
- The wizard should support both modes (toggle commercial/residential)

### 7. CRM Expansion on Clients
Expand the existing Clients section to be a lightweight CRM. Key data to store:

- General contractor companies
- Contacts per GC: estimators, sales contacts — with name, phone, email
- Link estimates/jobs to GC contacts (so a salesperson can pull up "what jobs did we bid with Big D Construction?")
- Notes / conversation log
- Attachments: save emails, PDFs

### 8. Room Tracking from CSV Import
- CSV from takeoff software already includes room assignments
- Make sure rooms are captured during import and stored per estimate
- Used by: Specific Inclusions section of proposal wizard, room-breakdown reporting

---

## Future / Backlog Ideas (not v1)

- **Clarification tagging during takeoff** — Blake tags clarifications in takeoff software; they export on the CSV in a different category. App should read this and pre-populate the Design Clarifications section.
- **Exclusion tagging** — Same: exclusions tagged during takeoff export on CSV, should pre-populate Exclusions section.
- **LLM-assisted room summary** — AI reads line items per room and generates a draft inclusion summary. Blake acknowledged "without building our own LLM... that's probably a next version thing."
- **Vendor email automation** — When Asana sync finds stale prices, auto-email vendor with a request for updated pricing; CC purchaser.
- **Budget vs Hard Bid mode** — Some proposals are "budgets" not "hard bids." Wording in the proposal changes. Should be a toggle.
- **Breakout by category** — Some clients want the estimate broken out by category. Sometimes simple, sometimes fairly custom. Needs further scoping.

---

## Proposal Template Reference

**Commercial template structure** (from actual Word doc):
```
[Company address / contact block]
[Date]
Dear [Estimator name],

Thank you for the opportunity to bid the [Job Name]. The proposal is based on 
plans dated [plan date] and addenda [list]. The total for the items listed 
below is $[amount] ([AMOUNT IN WORDS]).

Estimate Detail

Specification Sections:
  [list of spec numbers and titles]

Specific inclusions:
  [Millwork - $X; Countertop - $Y]
  [Room Name]
    - [bullet]
    - [bullet]
  ...

Design Clarifications:
  - [item]
  ...

Alternates (not included in base bid):
  Alternate #01 – [description] – [ADD/DEDUCT] $[amount]

Specific Exclusions:
  - [item]
  ...

Please feel free to contact me with any questions you may have.

Sincerely,
[Name]
[Phone]
[Email]
[Website]
```

**Standard Design Clarifications** (from template):
- All cabinet doors bid as slab and cabinet interiors bid as white melamine
- Drawers bid as slab fronts with ¾" white melamine drawers and soft close undermount drawer slides

**Standard Specific Exclusions** (from template):
- Man doors
- Install of owner supplied furnishings
- Demolition
- Sinks
- In-wall blocking
- Holiday/after-hours/overtime work
- AWI Certification
- FSC certified material
- LEED certification
- Bonding
- Permits/fees
- Protection of completed work
- Traffic control for deliveries

---

## Business Context

- Blake is sending out ~$29M/month in bids solo. Goal is to land 20% = ~$5-6M contracted. Department target: $2.5M/month.
- Company (TrimArt) wants to be "the cabinet company that harnesses AI" — boss wants a dramatically different-looking company in 3 months.
- Boss has asked Rob about coming on full-time (hybrid in-office). Rob is considering it. Boss wants to know compensation requirements by ~next week.
