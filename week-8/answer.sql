Day 1 is ready. The ER diagram is in `meal_er_diagram.dbml`. Paste it into dbdiagram.io (Import, or the editor on the left) and it draws the diagram. The one-page requirements summary is below.

## Requirements summary: MEAL Project Tracking System

**Purpose.** A central database where partner organizations plan projects, record activities and participants, report indicator results against targets, and track community feedback and complaints, so MEAL staff can produce donor reports without rebuilding spreadsheets every quarter.

**Users and roles**
- **Admin**: manages organizations, users and reference data.
- **MEAL officer**: defines indicators and targets, verifies data, produces reports.
- **Project officer**: plans activities and reviews progress.
- **Field enumerator**: enters activity, participant and indicator data for assigned locations.
- **Viewer** (donor or partner): read-only access to approved results.

**Functional requirements**
1. Hold a results framework per project (impact → outcome → output) with indicators, baselines, and targets per reporting period.
2. Record activities linked to an output and a location, with status and budget.
3. Register participants once, with sensitive fields protected, and link them to many activities.
4. Capture indicator values by period and location, disaggregated by sex and age group, with a draft → submitted → verified workflow.
5. Log community feedback and complaints (channel, category, status, resolution time).
6. Track reports per period and attach evidence files to activities or values.
7. Keep an audit trail of every change to critical tables.

**Non-functional requirements**
- **Multi-tenancy:** each organization sees only its own data (row-level security).
- **Privacy:** participant names encrypted, national IDs hashed, passwords hashed.
- **Performance:** indicator-versus-target queries stay fast as data grows.
- **Rebuildable:** the whole schema builds from an empty database through Flyway.

**Analytical questions the design must answer** (these feed Day 4)
- Achievement versus target per indicator, per period.
- Participants reached by sex, age group and location.
- Activities completed versus planned, and budget spent per output.
- Feedback cases still open after 30 days, grouped by category and location.
- Which locations are behind target.

## Cardinalities

| Relationship | Cardinality |
|---|---|
| Organization → Users | 1 : N |
| Organization → Projects | 1 : N |
| Donor → Projects | 1 : N |
| Projects ↔ Locations (`project_locations`) | M : N |
| Location → Location (hierarchy) | 1 : N (self) |
| Project → Results | 1 : N |
| Result → Result (impact → outcome → output) | 1 : N (self) |
| Result → Indicators | 1 : N |
| Indicator ↔ Reporting periods (`indicator_targets`) | M : N |
| Indicator → Indicator values | 1 : N |
| Project → Activities | 1 : N |
| Result (output) → Activities | 1 : N |
| Activities ↔ Participants (`activity_participants`) | M : N |
| Project → Feedback cases | 1 : N |
| Project + Period → Reports | 1 : N |
| Activity or Indicator value → Evidence files | 1 : N (each optional) |

## Questions to settle before any SQL

These are the design decisions I'd like feedback on, from you or your instructor:

1. **Results hierarchy.** I used one self-referencing `results` table instead of separate outcome and output tables. It is flexible and simpler to query, but it enforces less structure. Is that acceptable for your track?
2. **Multi-tenancy.** I put `org_id` directly on the high-volume tables (`indicator_values`, `feedback_cases`, `participants`) so row-level security policies stay simple and fast, at the cost of some redundancy with `projects.org_id`. Do you want projects shared across organizations (a consortium) instead? That would need a `project_members` table.
3. **Disaggregation.** Sex and age group are columns on `indicator_values`. If your indicators need other disaggregations (disability, displacement status), a separate `disaggregations` table would be better.
4. **Scope.** I left out surveys and questionnaires. If you want raw form submissions, that is a natural fit for MongoDB on Day 3.

MEAL ER DIAGRAM
// MEAL Project Tracking System - ER diagram (paste into dbdiagram.io)
// Multi-tenant: every business table carries org_id -> used by RLS on Day 2 (V4)

Table organizations {
  id uuid [pk]
  name varchar(150) [not null, unique]
  org_type varchar(30) [not null, note: 'lead | implementing_partner | donor_viewer']
  created_at timestamptz [not null]
}

Table users {
  id uuid [pk]
  org_id uuid [not null]
  full_name varchar(120) [not null]
  email varchar(150) [not null, unique]
  password_hash text [not null, note: 'bcrypt/argon2 hash, never plaintext']
  role varchar(30) [not null, note: 'admin | meal_officer | project_officer | field_enumerator | viewer']
  is_active boolean [not null]
  created_at timestamptz [not null]
}

Table donors {
  id uuid [pk]
  name varchar(150) [not null, unique]
  country varchar(60)
}

Table projects {
  id uuid [pk]
  org_id uuid [not null, note: 'owning / implementing organization']
  donor_id uuid [not null]
  code varchar(30) [not null, unique]
  name varchar(200) [not null]
  start_date date [not null]
  end_date date [not null]
  budget_amount numeric(14,2)
  currency char(3)
  status varchar(20) [not null, note: 'planned | active | closed']
}

Table locations {
  id uuid [pk]
  parent_id uuid [note: 'self-reference: country > county/district > ward/sub-county']
  name varchar(120) [not null]
  level varchar(20) [not null, note: 'country | county | district | ward | village']
  country_code char(2) [not null]
}

Table project_locations {
  project_id uuid [not null]
  location_id uuid [not null]
  indexes {
    (project_id, location_id) [pk]
  }
}

Table reporting_periods {
  id uuid [pk]
  project_id uuid [not null]
  label varchar(40) [not null, note: 'e.g. 2026-Q3']
  period_type varchar(15) [not null, note: 'monthly | quarterly | annual']
  start_date date [not null]
  end_date date [not null]
  indexes {
    (project_id, label) [unique]
  }
}

Table results {
  id uuid [pk]
  project_id uuid [not null]
  parent_id uuid [note: 'self-reference: impact > outcome > output']
  level varchar(15) [not null, note: 'impact | outcome | output']
  code varchar(20) [not null, note: 'e.g. 1.1']
  title varchar(250) [not null]
  indexes {
    (project_id, code) [unique]
  }
}

Table indicators {
  id uuid [pk]
  result_id uuid [not null]
  code varchar(30) [not null]
  name varchar(250) [not null]
  unit varchar(40) [not null, note: 'persons | households | percent | count']
  indicator_type varchar(15) [not null, note: 'number | percentage | cumulative']
  baseline_value numeric(14,2)
  is_disaggregated_by_sex boolean [not null]
  is_disaggregated_by_age boolean [not null]
  frequency varchar(15) [not null, note: 'monthly | quarterly | annual']
}

Table indicator_targets {
  id uuid [pk]
  indicator_id uuid [not null]
  period_id uuid [not null]
  target_value numeric(14,2) [not null]
  indexes {
    (indicator_id, period_id) [unique]
  }
}

Table activities {
  id uuid [pk]
  project_id uuid [not null]
  result_id uuid [not null, note: 'output the activity contributes to']
  location_id uuid [not null]
  title varchar(250) [not null]
  planned_start date
  planned_end date
  actual_date date
  budget_amount numeric(14,2)
  status varchar(15) [not null, note: 'planned | ongoing | completed | cancelled']
  created_by uuid [not null]
}

Table participants {
  id uuid [pk]
  org_id uuid [not null]
  participant_code varchar(30) [not null, unique, note: 'pseudonymous ID used in reports']
  full_name_enc bytea [not null, note: 'encrypted (pgcrypto)']
  national_id_hash text [note: 'salted hash, for de-duplication only']
  sex char(1) [not null, note: 'F | M | O']
  birth_year smallint
  location_id uuid [not null]
}

Table activity_participants {
  activity_id uuid [not null]
  participant_id uuid [not null]
  role varchar(30) [note: 'trainee | beneficiary | facilitator | leader']
  indexes {
    (activity_id, participant_id) [pk]
  }
}

Table indicator_values {
  id uuid [pk]
  org_id uuid [not null]
  indicator_id uuid [not null]
  period_id uuid [not null]
  location_id uuid [not null]
  activity_id uuid [note: 'optional source activity']
  sex char(1) [note: 'null when not disaggregated']
  age_group varchar(10) [note: 'e.g. 0-17, 18-35, 36+']
  value numeric(14,2) [not null]
  status varchar(15) [not null, note: 'draft | submitted | verified | rejected']
  submitted_by uuid [not null]
  verified_by uuid
  submitted_at timestamptz [not null]
  verified_at timestamptz
}

Table feedback_cases {
  id uuid [pk]
  org_id uuid [not null]
  project_id uuid [not null]
  location_id uuid [not null]
  activity_id uuid
  channel varchar(20) [not null, note: 'hotline | suggestion_box | meeting | in_person']
  category varchar(30) [not null, note: 'feedback | complaint | sensitive']
  description text [not null]
  status varchar(15) [not null, note: 'open | in_progress | resolved | closed']
  received_at timestamptz [not null]
  resolved_at timestamptz
  handled_by uuid
}

Table reports {
  id uuid [pk]
  org_id uuid [not null]
  project_id uuid [not null]
  period_id uuid [not null]
  report_type varchar(20) [not null, note: 'monthly | quarterly | annual | donor']
  status varchar(15) [not null, note: 'draft | submitted | approved']
  prepared_by uuid [not null]
  submitted_at timestamptz
}

Table evidence_files {
  id uuid [pk]
  org_id uuid [not null]
  activity_id uuid
  indicator_value_id uuid
  file_name varchar(200) [not null]
  storage_uri text [not null]
  uploaded_by uuid [not null]
  uploaded_at timestamptz [not null]
}

Table audit_log {
  id bigint [pk, note: 'identity; populated by triggers in V3']
  org_id uuid
  table_name varchar(60) [not null]
  record_id uuid [not null]
  action varchar(10) [not null, note: 'INSERT | UPDATE | DELETE']
  old_data jsonb
  new_data jsonb
  changed_by uuid
  changed_at timestamptz [not null]
}

// ---------- Relationships (many-to-one: child > parent) ----------
Ref: users.org_id > organizations.id
Ref: projects.org_id > organizations.id
Ref: projects.donor_id > donors.id
Ref: locations.parent_id > locations.id
Ref: project_locations.project_id > projects.id
Ref: project_locations.location_id > locations.id
Ref: reporting_periods.project_id > projects.id
Ref: results.project_id > projects.id
Ref: results.parent_id > results.id
Ref: indicators.result_id > results.id
Ref: indicator_targets.indicator_id > indicators.id
Ref: indicator_targets.period_id > reporting_periods.id
Ref: activities.project_id > projects.id
Ref: activities.result_id > results.id
Ref: activities.location_id > locations.id
Ref: activities.created_by > users.id
Ref: participants.org_id > organizations.id
Ref: participants.location_id > locations.id
Ref: activity_participants.activity_id > activities.id
Ref: activity_participants.participant_id > participants.id
Ref: indicator_values.org_id > organizations.id
Ref: indicator_values.indicator_id > indicators.id
Ref: indicator_values.period_id > reporting_periods.id
Ref: indicator_values.location_id > locations.id
Ref: indicator_values.activity_id > activities.id
Ref: indicator_values.submitted_by > users.id
Ref: indicator_values.verified_by > users.id
Ref: feedback_cases.org_id > organizations.id
Ref: feedback_cases.project_id > projects.id
Ref: feedback_cases.location_id > locations.id
Ref: feedback_cases.activity_id > activities.id
Ref: feedback_cases.handled_by > users.id
Ref: reports.org_id > organizations.id
Ref: reports.project_id > projects.id
Ref: reports.period_id > reporting_periods.id
Ref: reports.prepared_by > users.id
Ref: evidence_files.org_id > organizations.id
Ref: evidence_files.activity_id > activities.id
Ref: evidence_files.indicator_value_id > indicator_values.id
Ref: evidence_files.uploaded_by > users.id
Ref: audit_log.changed_by > users.id


CORE TABLES 
-- V1: core tables (PostgreSQL 15+; uses UNIQUE NULLS NOT DISTINCT)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE organizations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        varchar(150) NOT NULL UNIQUE,
  org_type    varchar(30)  NOT NULL CHECK (org_type IN ('lead','implementing_partner','donor_viewer')),
  created_at  timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id         uuid NOT NULL REFERENCES organizations(id),
  full_name      varchar(120) NOT NULL,
  email          varchar(150) NOT NULL UNIQUE,
  password_hash  text NOT NULL,
  role           varchar(30) NOT NULL CHECK (role IN ('admin','meal_officer','project_officer','field_enumerator','viewer')),
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE donors (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name     varchar(150) NOT NULL UNIQUE,
  country  varchar(60)
);

CREATE TABLE projects (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id         uuid NOT NULL REFERENCES organizations(id),
  donor_id       uuid NOT NULL REFERENCES donors(id),
  code           varchar(30)  NOT NULL UNIQUE,
  name           varchar(200) NOT NULL,
  start_date     date NOT NULL,
  end_date       date NOT NULL,
  budget_amount  numeric(14,2) CHECK (budget_amount >= 0),
  currency       char(3),
  status         varchar(20) NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','active','closed')),
  CHECK (end_date >= start_date)
);

CREATE TABLE locations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id     uuid REFERENCES locations(id),
  name          varchar(120) NOT NULL,
  level         varchar(20)  NOT NULL CHECK (level IN ('country','county','district','ward','village')),
  country_code  char(2) NOT NULL
);

CREATE TABLE project_locations (
  project_id   uuid NOT NULL REFERENCES projects(id)  ON DELETE CASCADE,
  location_id  uuid NOT NULL REFERENCES locations(id),
  PRIMARY KEY (project_id, location_id)
);

CREATE TABLE reporting_periods (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id   uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  label        varchar(40) NOT NULL,
  period_type  varchar(15) NOT NULL CHECK (period_type IN ('monthly','quarterly','annual')),
  start_date   date NOT NULL,
  end_date     date NOT NULL,
  UNIQUE (project_id, label),
  CHECK (end_date >= start_date)
);

CREATE TABLE results (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  parent_id   uuid REFERENCES results(id),
  level       varchar(15)  NOT NULL CHECK (level IN ('impact','outcome','output')),
  code        varchar(20)  NOT NULL,
  title       varchar(250) NOT NULL,
  UNIQUE (project_id, code)
);

CREATE TABLE indicators (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id                uuid NOT NULL REFERENCES results(id) ON DELETE CASCADE,
  code                     varchar(30)  NOT NULL,
  name                     varchar(250) NOT NULL,
  unit                     varchar(40)  NOT NULL,
  indicator_type           varchar(15)  NOT NULL CHECK (indicator_type IN ('number','percentage','cumulative')),
  baseline_value           numeric(14,2),
  is_disaggregated_by_sex  boolean NOT NULL DEFAULT false,
  is_disaggregated_by_age  boolean NOT NULL DEFAULT false,
  frequency                varchar(15) NOT NULL CHECK (frequency IN ('monthly','quarterly','annual')),
  UNIQUE (result_id, code)
);

CREATE TABLE indicator_targets (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  indicator_id  uuid NOT NULL REFERENCES indicators(id) ON DELETE CASCADE,
  period_id     uuid NOT NULL REFERENCES reporting_periods(id) ON DELETE CASCADE,
  target_value  numeric(14,2) NOT NULL CHECK (target_value >= 0),
  UNIQUE (indicator_id, period_id)
);

CREATE TABLE activities (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id     uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  result_id      uuid NOT NULL REFERENCES results(id),
  location_id    uuid NOT NULL REFERENCES locations(id),
  title          varchar(250) NOT NULL,
  planned_start  date,
  planned_end    date,
  actual_date    date,
  budget_amount  numeric(14,2) CHECK (budget_amount >= 0),
  status         varchar(15) NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','ongoing','completed','cancelled')),
  created_by     uuid NOT NULL REFERENCES users(id),
  CHECK (planned_end IS NULL OR planned_start IS NULL OR planned_end >= planned_start)
);

CREATE TABLE participants (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            uuid NOT NULL REFERENCES organizations(id),
  participant_code  varchar(30) NOT NULL UNIQUE,
  full_name_enc     bytea NOT NULL,          -- pgp_sym_encrypt(name, key)
  national_id_hash  text,                    -- sha256(pepper || id), de-duplication only
  sex               char(1) NOT NULL CHECK (sex IN ('F','M','O')),
  birth_year        smallint CHECK (birth_year BETWEEN 1900 AND 2100),
  location_id       uuid NOT NULL REFERENCES locations(id)
);

CREATE TABLE activity_participants (
  activity_id    uuid NOT NULL REFERENCES activities(id)   ON DELETE CASCADE,
  participant_id uuid NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
  role           varchar(30) CHECK (role IN ('trainee','beneficiary','facilitator','leader')),
  PRIMARY KEY (activity_id, participant_id)
);

CREATE TABLE indicator_values (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid NOT NULL REFERENCES organizations(id),
  indicator_id  uuid NOT NULL REFERENCES indicators(id),
  period_id     uuid NOT NULL REFERENCES reporting_periods(id),
  location_id   uuid NOT NULL REFERENCES locations(id),
  activity_id   uuid REFERENCES activities(id),
  sex           char(1) CHECK (sex IN ('F','M','O')),
  age_group     varchar(10) CHECK (age_group IN ('0-17','18-35','36+')),
  value         numeric(14,2) NOT NULL CHECK (value >= 0),
  status        varchar(15) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','verified','rejected')),
  submitted_by  uuid NOT NULL REFERENCES users(id),
  verified_by   uuid REFERENCES users(id),
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  verified_at   timestamptz,
  -- one value per indicator/period/location/disaggregation cell
  UNIQUE NULLS NOT DISTINCT (indicator_id, period_id, location_id, sex, age_group),
  -- four-eyes principle: verifier must be a different person
  CHECK (status <> 'verified' OR (verified_by IS NOT NULL AND verified_by <> submitted_by))
);

CREATE TABLE feedback_cases (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       uuid NOT NULL REFERENCES organizations(id),
  project_id   uuid NOT NULL REFERENCES projects(id),
  location_id  uuid NOT NULL REFERENCES locations(id),
  activity_id  uuid REFERENCES activities(id),
  channel      varchar(20) NOT NULL CHECK (channel IN ('hotline','suggestion_box','meeting','in_person')),
  category     varchar(30) NOT NULL CHECK (category IN ('feedback','complaint','sensitive')),
  description  text NOT NULL,
  status       varchar(15) NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved','closed')),
  received_at  timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz,
  handled_by   uuid REFERENCES users(id),
  CHECK (status NOT IN ('resolved','closed') OR resolved_at IS NOT NULL)
);

CREATE TABLE reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid NOT NULL REFERENCES organizations(id),
  project_id    uuid NOT NULL REFERENCES projects(id),
  period_id     uuid NOT NULL REFERENCES reporting_periods(id),
  report_type   varchar(20) NOT NULL CHECK (report_type IN ('monthly','quarterly','annual','donor')),
  status        varchar(15) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','approved')),
  prepared_by   uuid NOT NULL REFERENCES users(id),
  submitted_at  timestamptz
);

CREATE TABLE evidence_files (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id              uuid NOT NULL REFERENCES organizations(id),
  activity_id         uuid REFERENCES activities(id),
  indicator_value_id  uuid REFERENCES indicator_values(id),
  file_name           varchar(200) NOT NULL,
  storage_uri         text NOT NULL,
  uploaded_by         uuid NOT NULL REFERENCES users(id),
  uploaded_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (activity_id IS NOT NULL OR indicator_value_id IS NOT NULL)
);

CREATE TABLE audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  org_id      uuid,
  table_name  varchar(60) NOT NULL,
  record_id   uuid NOT NULL,
  action      varchar(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  old_data    jsonb,
  new_data    jsonb,
  changed_by  uuid,
  changed_at  timestamptz NOT NULL DEFAULT now()
);


INDEXES
-- V2: foreign-key and basic lookup indexes only.
-- Analytical/composite/partial indexes are deliberately NOT here: Day 4 adds them
-- (as V6) AFTER the BEFORE plans have been captured with EXPLAIN ANALYZE.
-- PK and UNIQUE constraints already create their own indexes.

CREATE INDEX idx_users_org                  ON users (org_id);
CREATE INDEX idx_projects_org               ON projects (org_id);
CREATE INDEX idx_projects_donor             ON projects (donor_id);
CREATE INDEX idx_locations_parent           ON locations (parent_id);
CREATE INDEX idx_project_locations_location ON project_locations (location_id);
CREATE INDEX idx_results_parent             ON results (parent_id);
CREATE INDEX idx_indicators_result          ON indicators (result_id);
CREATE INDEX idx_targets_period             ON indicator_targets (period_id);
CREATE INDEX idx_activities_project         ON activities (project_id);
CREATE INDEX idx_activities_result          ON activities (result_id);
CREATE INDEX idx_activities_location        ON activities (location_id);
CREATE INDEX idx_participants_org           ON participants (org_id);
CREATE INDEX idx_participants_location      ON participants (location_id);
CREATE INDEX idx_act_participants_part      ON activity_participants (participant_id);
CREATE INDEX idx_values_org                 ON indicator_values (org_id);
CREATE INDEX idx_values_period              ON indicator_values (period_id);
CREATE INDEX idx_values_location            ON indicator_values (location_id);
CREATE INDEX idx_values_activity            ON indicator_values (activity_id);
CREATE INDEX idx_feedback_org               ON feedback_cases (org_id);
CREATE INDEX idx_feedback_project           ON feedback_cases (project_id);
CREATE INDEX idx_feedback_location          ON feedback_cases (location_id);
CREATE INDEX idx_reports_project_period     ON reports (project_id, period_id);
CREATE INDEX idx_evidence_activity          ON evidence_files (activity_id);
CREATE INDEX idx_evidence_value             ON evidence_files (indicator_value_id);
CREATE INDEX idx_audit_record               ON audit_log (table_name, record_id);
CREATE INDEX idx_audit_changed_at           ON audit_log (changed_at);



AUDIT AND TRIGGERS
-- V3: audit trail + business-rule triggers

-- Generic audit trigger. SECURITY DEFINER so the app role can never write to
-- (or bypass) audit_log directly. Secrets are stripped from the stored JSON.
CREATE OR REPLACE FUNCTION audit_row_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_old  jsonb;
  v_new  jsonb;
  v_row  jsonb;
  v_user uuid;
BEGIN
  v_user := NULLIF(current_setting('app.current_user_id', true), '')::uuid;
  IF TG_OP = 'INSERT' THEN
    v_new := to_jsonb(NEW) - 'password_hash' - 'full_name_enc' - 'national_id_hash';
    v_row := v_new;
  ELSIF TG_OP = 'UPDATE' THEN
    v_old := to_jsonb(OLD) - 'password_hash' - 'full_name_enc' - 'national_id_hash';
    v_new := to_jsonb(NEW) - 'password_hash' - 'full_name_enc' - 'national_id_hash';
    v_row := v_new;
  ELSE
    v_old := to_jsonb(OLD) - 'password_hash' - 'full_name_enc' - 'national_id_hash';
    v_row := v_old;
  END IF;

  INSERT INTO audit_log (org_id, table_name, record_id, action, old_data, new_data, changed_by)
  VALUES ((v_row->>'org_id')::uuid, TG_TABLE_NAME, (v_row->>'id')::uuid, TG_OP, v_old, v_new, v_user);

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['users','projects','activities','participants',
                           'indicator_values','feedback_cases','reports']
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_audit_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$I
         FOR EACH ROW EXECUTE FUNCTION audit_row_change()', t);
  END LOOP;
END $$;

-- The audit log is append-only, even for the table owner.
CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only (% blocked)', TG_OP;
END $$;

CREATE TRIGGER trg_audit_log_immutable
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();

-- Verified indicator values are locked; stamp verified_at automatically.
CREATE OR REPLACE FUNCTION indicator_value_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'verified' AND (
       NEW.value        IS DISTINCT FROM OLD.value OR
       NEW.indicator_id IS DISTINCT FROM OLD.indicator_id OR
       NEW.period_id    IS DISTINCT FROM OLD.period_id OR
       NEW.location_id  IS DISTINCT FROM OLD.location_id) THEN
    RAISE EXCEPTION 'Verified indicator value % is locked; reject it first to change it', OLD.id;
  END IF;
  IF NEW.status = 'verified' AND OLD.status <> 'verified' THEN
    NEW.verified_at := now();
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_indicator_value_guard
  BEFORE UPDATE ON indicator_values
  FOR EACH ROW EXECUTE FUNCTION indicator_value_guard();

-- Auto-stamp resolved_at when a feedback case is resolved/closed.
CREATE OR REPLACE FUNCTION feedback_resolved_stamp() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('resolved','closed') AND NEW.resolved_at IS NULL THEN
    NEW.resolved_at := now();
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_feedback_resolved_stamp
  BEFORE INSERT OR UPDATE ON feedback_cases
  FOR EACH ROW EXECUTE FUNCTION feedback_resolved_stamp();

ROW LEVEL SECURITY
-- V4: least-privilege roles, grants, row-level security
-- Roles are cluster-wide and survive `flyway clean`, so creation is guarded.
-- NOLOGIN group roles: create the real login OUTSIDE migrations, e.g.
--   CREATE ROLE meal_api LOGIN PASSWORD '<from secret store>' IN ROLE meal_app;
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'meal_app')      THEN CREATE ROLE meal_app      NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'meal_readonly') THEN CREATE ROLE meal_readonly NOLOGIN; END IF;
END $$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO meal_app, meal_readonly;

-- Tenant context: the app sets these per transaction (parameterized):
--   SELECT set_config('app.current_org_id',  $1, true);
--   SELECT set_config('app.current_user_id', $2, true);
CREATE OR REPLACE FUNCTION current_org_id() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.current_org_id', true), '')::uuid $$;

-- ---------- Grants ----------
-- Reference data: read-only
GRANT SELECT ON donors, locations TO meal_app, meal_readonly;

-- Secrets are never selectable by the app: no password_hash, no national_id_hash
GRANT SELECT (id, org_id, full_name, email, role, is_active, created_at) ON users TO meal_app, meal_readonly;
GRANT SELECT (id, org_id, participant_code, full_name_enc, sex, birth_year, location_id) ON participants TO meal_app, meal_readonly;
GRANT INSERT ON participants TO meal_app;
GRANT UPDATE (sex, birth_year, location_id) ON participants TO meal_app;

GRANT SELECT ON organizations, projects, project_locations, reporting_periods, results, indicators,
                indicator_targets, activities, activity_participants, indicator_values,
                feedback_cases, reports, evidence_files, audit_log
  TO meal_app, meal_readonly;

GRANT INSERT, UPDATE ON projects, results, indicators, indicator_targets, reporting_periods,
                        activities, indicator_values, feedback_cases, reports TO meal_app;
GRANT INSERT, DELETE ON project_locations, activity_participants, evidence_files TO meal_app;
-- no DELETE on core business tables, no write access at all to audit_log

-- ---------- Row-level security ----------
-- Tables carrying org_id: direct tenant isolation
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['users','participants','projects','indicator_values',
                           'feedback_cases','reports','evidence_files','audit_log']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY org_isolation ON %I FOR ALL TO meal_app, meal_readonly
         USING (org_id = current_org_id()) WITH CHECK (org_id = current_org_id())', t);
  END LOOP;
END $$;

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_self ON organizations FOR SELECT TO meal_app, meal_readonly
  USING (id = current_org_id());

-- Child tables: inherit visibility from the parent (parent's RLS applies inside EXISTS)
ALTER TABLE project_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY via_project ON project_locations FOR ALL TO meal_app, meal_readonly
  USING (EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id));

ALTER TABLE reporting_periods ENABLE ROW LEVEL SECURITY;
CREATE POLICY via_project ON reporting_periods FOR ALL TO meal_app, meal_readonly
  USING (EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id));

ALTER TABLE results ENABLE ROW LEVEL SECURITY;
CREATE POLICY via_project ON results FOR ALL TO meal_app, meal_readonly
  USING (EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id));

ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY via_project ON activities FOR ALL TO meal_app, meal_readonly
  USING (EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id));

ALTER TABLE indicators ENABLE ROW LEVEL SECURITY;
CREATE POLICY via_result ON indicators FOR ALL TO meal_app, meal_readonly
  USING (EXISTS (SELECT 1 FROM results r WHERE r.id = result_id));

ALTER TABLE indicator_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY via_indicator ON indicator_targets FOR ALL TO meal_app, meal_readonly
  USING (EXISTS (SELECT 1 FROM indicators i WHERE i.id = indicator_id));

ALTER TABLE activity_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY via_activity ON activity_participants FOR ALL TO meal_app, meal_readonly
  USING (EXISTS (SELECT 1 FROM activities a WHERE a.id = activity_id));

-- Table owner (the migration user) bypasses RLS on purpose; the app never connects as owner.

-- Login check without exposing password_hash to the app role
CREATE OR REPLACE FUNCTION verify_login(p_email text, p_password text)
RETURNS TABLE (user_id uuid, org_id uuid, role varchar)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT u.id, u.org_id, u.role
  FROM users u
  WHERE u.email = p_email AND u.is_active AND u.password_hash = crypt(p_password, u.password_hash)
$$;
REVOKE ALL ON FUNCTION verify_login(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION verify_login(text, text) TO meal_app;
