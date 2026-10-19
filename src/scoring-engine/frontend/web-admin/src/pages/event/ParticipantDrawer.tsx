import { useState } from "react";
import { ArrowLeft, X } from "lucide-react";
import { Drawer, Loading, StatusBadge } from "@shared/components/ui";
import { api } from "../../lib/api";
import { relTime } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";
import type { SubmissionRow } from "@shared/lib/types";
import SubmissionDetail from "./SubmissionDetail";

export default function ParticipantDrawer({ eventId, participantId, onClose }: {
  eventId: string; participantId: string; onClose: () => void;
}) {
  const { data, reload } = useLoad(
    () => api.get<{ items: SubmissionRow[] }>(`/api/admin/events/${eventId}/submissions?participant_id=${participantId}&limit=200`),
    [participantId],
  );
  const [open, setOpen] = useState<string | null>(null);
  const first = data?.items[0];

  return (
    <Drawer onClose={onClose}>
      {open ? (
        <>
          <div style={{ padding: "12px 22px 0" }}>
            <button className="btn btn-sm btn-ghost" onClick={() => setOpen(null)}><ArrowLeft size={14} /> All submissions</button>
          </div>
          <SubmissionDetail id={open} onClose={onClose} onChanged={() => void reload()} />
        </>
      ) : (
        <>
          <div className="modal-head">
            <div>
              <h3>{first?.participant ?? "Participant"}</h3>
              <div className="faint small">{first?.upn} · {first?.external_id}</div>
            </div>
            <button className="btn btn-ghost icon-btn" onClick={onClose} aria-label="Close"><X size={18} /></button>
          </div>
          {!data ? <Loading /> : (
            <table className="plain">
              <thead><tr><th>Step</th><th>Result</th><th>Why</th><th className="num">When</th></tr></thead>
              <tbody>
                {data.items.map((s) => (
                  <tr key={s.id} className="clickable" onClick={() => setOpen(s.id)}>
                    <td>{s.step_title}<div className="faint small mono">{s.use_case}/{s.step}</div></td>
                    <td><StatusBadge status={s.status} /></td>
                    <td className="small muted">{s.reasons[0]?.message ?? ""}</td>
                    <td className="num faint small">{relTime(s.received_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}
    </Drawer>
  );
}
