export type SubStatus = "queued" | "evaluating" | "complete" | "incomplete" | "error";
export type StepState = "complete" | "incomplete" | "error" | "not_started" | "evaluating";

export interface Integration {
  id: string;
  name: string;
  vendor: string;
  client_id: string;
  secret_hint: string;
  status: "active" | "revoked";
  webhook_url: string | null;
  has_webhook_secret: boolean;
  created_at: string;
  secret_rotated_at: string;
  last_used_at: string | null;
  submissions?: number;
  client_secret?: string;
  webhook_secret?: string;
}

export interface EventSummary {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  starts_at: string | null;
  ends_at: string | null;
  status: "draft" | "live" | "closed";
  public_leaderboard: boolean;
  public_name_format: "full" | "first_last_initial" | "first_only";
  public_show_reasons: boolean;
  roster_group_id: string | null;
  last_synced_at: string | null;
  created_at: string;
  participants?: number;
  submissions?: number;
}

export interface StepDef {
  id: string;
  use_case_id: string;
  code: string;
  title: string;
  description: string | null;
  sort_order: number;
  rubric_yaml: string;
  rubric_version: number;
  check_count: number;
  updated_at: string;
}

export interface UseCaseDef {
  id: string;
  code: string;
  title: string;
  description: string | null;
  sort_order: number;
  steps: StepDef[];
}

export interface EventDetail extends EventSummary {
  use_cases: UseCaseDef[];
}

export interface Reason {
  check: string;
  message: string;
}

export interface SubmissionRow {
  id: string;
  status: SubStatus;
  event_id: string;
  event_slug: string;
  use_case: string;
  step: string;
  step_title: string;
  participant: string;
  participant_id: string;
  external_id: string;
  upn: string | null;
  received_at: string;
  evaluated_at: string | null;
  reasons: Reason[];
  attempts: number;
  verification_status: string;
  override_by: string | null;
  source: "vendor" | "sync";
  evidence_at: string | null;
}

export interface CheckResult {
  id: string;
  type: string;
  mode: "blocking" | "deferred";
  description: string;
  status: "passed" | "failed" | "error" | "pending";
  message: string;
  evidence: Record<string, unknown>;
}

export interface SubmissionDetail extends SubmissionRow {
  check_results: CheckResult[];
  lab_profile_id: string | null;
  lab_instance_id: string | null;
  lab_started_at: string;
  submitted_at: string;
  rubric_version: number;
  override_note: string | null;
  vendor_view: unknown;
}

export interface BoardStep {
  id: string;
  code: string;
  title: string;
  use_case: string;
  use_case_code: string;
  completed_count: number;
}

export interface BoardRow {
  rank: number | null;
  public_id: string;
  name: string;
  completed_steps: number;
  total_steps: number;
  attempts: number;
  last_completed_at: string | null;
  elapsed_seconds: number | null;
  steps: Record<string, StepState>;
  verification: Record<string, string>;
  participant_id?: string;
  external_id?: string;
  email?: string | null;
  upn?: string | null;
}

export interface Board {
  event: { id?: string; slug: string; name: string; status: string };
  steps: BoardStep[];
  participants_total: number;
  finished_total: number;
  rows: BoardRow[];
  generated_at: string;
}

export interface Overview {
  events: number;
  live_events: number;
  integrations: number;
  participants: number;
  submissions: number;
  submissions_last_hour: number;
  by_status: Record<SubStatus, number>;
  pending_verification: number;
  recent: SubmissionRow[];
}

export interface CheckType {
  type: string;
  title: string;
  summary: string;
  example: Record<string, unknown>;
}
