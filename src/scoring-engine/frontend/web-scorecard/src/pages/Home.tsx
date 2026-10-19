import { Link, Navigate } from "react-router-dom";
import { ChevronRight, IdCard } from "lucide-react";
import { TopBar } from "@shared/components/TopBar";
import { Empty, Loading, StatusBadge } from "@shared/components/ui";
import { useLoad } from "@shared/lib/hooks";
import { api } from "../lib/api";

interface PublicEvent { slug: string; name: string; description: string | null; status: string }

export default function Home() {
  const { data } = useLoad(() => api.get<PublicEvent[]>("/api/public/events"));
  if (data && data.length === 1) return <Navigate to={`/${data[0].slug}`} replace />;
  return (
    <div className="app">
      <TopBar area="Scorecard" />
      <div className="pub-body">
        <div className="hero">
          <div className="hero-eyebrow">Participant Scorecard</div>
          <h1>Check your lab progress</h1>
          <p>Choose your event, then enter your lab account to see which steps are complete and what is left to do.</p>
        </div>
        <div className="card">
          <div className="panel-head">
            <div><h3><IdCard size={16} className="faint" /> Events</h3><div className="sub">Events with scorecards available</div></div>
          </div>
          {!data ? <Loading /> : data.length === 0 ? (
            <Empty icon={<IdCard size={20} />} title="No scorecards available right now">Check back when your event starts.</Empty>
          ) : data.map((e) => (
            <Link key={e.slug} to={`/${e.slug}`} className="panel-item">
              <span className="tone tone-blue"><IdCard size={15} /></span>
              <div className="grow">
                <div className="pi-title">{e.name}</div>
                <div className="pi-sub">{e.description}</div>
              </div>
              <StatusBadge status={e.status} />
              <ChevronRight size={16} className="chev" />
            </Link>
          ))}
        </div>
        <div className="pub-foot">VectorSense Labs · Scoring Engine</div>
      </div>
    </div>
  );
}
