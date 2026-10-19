import { useState } from "react";
import { useParams } from "react-router-dom";
import { ExternalLink, ListChecks, Settings, Trophy, Inbox } from "lucide-react";
import { PageHeader } from "../components/Layout";
import { ErrorAlert, Loading, StatusBadge } from "@shared/components/ui";
import { api } from "../lib/api";
import { config } from "@shared/lib/config";
import { useLoad } from "@shared/lib/hooks";
import type { EventDetail } from "@shared/lib/types";
import LeaderboardTab from "./event/LeaderboardTab";
import SettingsTab from "./event/SettingsTab";
import StepsTab from "./event/StepsTab";
import SubmissionsTab from "./event/SubmissionsTab";

type Tab = "leaderboard" | "steps" | "submissions" | "settings";

export default function EventDetailPage() {
  const { eventId = "" } = useParams();
  const { data: event, error, reload } = useLoad(() => api.get<EventDetail>(`/api/admin/events/${eventId}`), [eventId]);
  const [tab, setTab] = useState<Tab>("leaderboard");

  if (!event) return <><ErrorAlert error={error} />{!error && <Loading />}</>;
  const stepCount = event.use_cases.reduce((n, u) => n + u.steps.length, 0);
  const publicUrl = `${config().scorecard_base_url}/${event.slug}`;

  return (
    <>
      <PageHeader
        crumbs={[{ label: "Events", to: "/events" }, { label: event.slug }]}
        title={<span className="row">{event.name} <StatusBadge status={event.status} /></span>}
        sub={<>event_id <code>{event.slug}</code> · {event.use_cases.length} use cases · {stepCount} steps</>}
        actions={event.public_leaderboard && event.status !== "draft" && (
          <a className="btn" href={publicUrl} target="_blank" rel="noreferrer"><ExternalLink size={15} /> Participant Scorecard</a>
        )}
      />
      <div>
        <div className="tabs">
          <button className={`tab ${tab === "leaderboard" ? "active" : ""}`} onClick={() => setTab("leaderboard")}><Trophy size={15} /> Leaderboard</button>
          <button className={`tab ${tab === "steps" ? "active" : ""}`} onClick={() => setTab("steps")}><ListChecks size={15} /> Use cases &amp; rubrics</button>
          <button className={`tab ${tab === "submissions" ? "active" : ""}`} onClick={() => setTab("submissions")}><Inbox size={15} /> Submissions</button>
          <button className={`tab ${tab === "settings" ? "active" : ""}`} onClick={() => setTab("settings")}><Settings size={15} /> Settings</button>
        </div>
        {tab === "leaderboard" && <LeaderboardTab event={event} />}
        {tab === "steps" && <StepsTab event={event} reload={reload} />}
        {tab === "submissions" && <SubmissionsTab event={event} />}
        {tab === "settings" && <SettingsTab event={event} reload={reload} />}
      </div>
    </>
  );
}
