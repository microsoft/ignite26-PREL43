"""Simulates a lab platform (lab partner) driving the scoring API end to end.

For every simulated participant it (1) writes Microsoft 365 "evidence" into the mock Graph file the worker
reads, then (2) clicks Complete via the real vendor API: OAuth2 client credentials -> POST /v1/steps/complete.
Some participants click before doing the work, so you see incomplete results with reasons, then retries.

    python scripts/vendor_simulator.py --api http://api:8000 --credentials samples/local/demo_credentials.json \
        --mock-file samples/local/mock_graph.json --participants 40 --speed 1.0
"""
import argparse
import json
import os
import random
import time
import uuid
from datetime import datetime, timedelta, timezone

import httpx

FIRST = ["Asha", "Liam", "Mei", "Carlos", "Fatima", "Noah", "Priya", "Lucas", "Aiko", "Omar", "Sofia", "Ethan",
         "Zara", "Mateo", "Hannah", "Ravi", "Elena", "Kofi", "Ingrid", "Diego", "Yara", "Tomás", "Nadia", "Jonas",
         "Leila", "Arjun", "Chloe", "Felix", "Amara", "Hugo", "Sana", "Mikael", "Isla", "Kenji", "Lucia", "Ade",
         "Freya", "Sami", "Olivia", "Rohan"]
LAST = ["Kumar", "Walsh", "Chen", "Rivera", "Haddad", "Becker", "Nair", "Martin", "Tanaka", "Farouk", "Rossi",
        "Clarke", "Ahmed", "Lopez", "Schmidt", "Iyer", "Petrova", "Mensah", "Larsen", "Torres", "Saleh", "Silva",
        "Novak", "Weber", "Karimi", "Menon", "Dubois", "Braun", "Okafor", "Moreau", "Qureshi", "Virtanen", "Reid",
        "Sato", "Garcia", "Adeyemi", "Nielsen", "Haddad", "Brown", "Pillai"]

STEPS = [("cowork-sales-brief", "step-1"), ("cowork-sales-brief", "step-2"), ("cowork-sales-brief", "step-3"),
         ("cowork-sales-brief", "step-4"), ("cowork-weekly-report", "step-1"), ("cowork-weekly-report", "step-2")]


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class MockTenant:
    def __init__(self, path: str) -> None:
        self.path = path
        self.data = {"users": {}}  # only the accounts this simulator owns

    def user(self, upn: str) -> dict:
        return self.data["users"].setdefault(upn, {"drive": {}, "file_contents": {}, "sent_messages": [],
                                                   "calendar_events": [], "copilot_interactions": [],
                                                   "copilot_audit": []})

    def file(self, upn: str, name: str, text: str) -> None:
        u = self.user(upn)
        item_id = uuid.uuid4().hex
        now = iso(datetime.now(timezone.utc))
        u["drive"].setdefault("/Cowork", []).append({
            "id": item_id, "name": name, "file": {"mimeType": "application/octet-stream"}, "size": len(text),
            "createdDateTime": now, "lastModifiedDateTime": now,
            "createdBy": {"user": {"email": upn, "displayName": upn.split("@")[0]}},
            "lastModifiedBy": {"user": {"email": upn}}, "parentReference": {"driveId": "mock", "path": "/Cowork"}})
        u["file_contents"][item_id] = text

    def profile(self, p: dict) -> None:
        self.user(p["upn"])["profile"] = {"givenName": p["first"], "surname": p["last"], "mail": p["email"]}

    def evidence(self, upn: str, use_case: str, step: str, *, with_copilot: bool) -> None:
        now = iso(datetime.now(timezone.utc))
        u = self.user(upn)
        if (use_case, step) == ("cowork-sales-brief", "step-1"):
            self.file(upn, "Contoso account brief.docx", "Contoso Ltd account brief: priorities, risks, next steps.")
            if with_copilot:
                u["copilot_interactions"].append({"id": uuid.uuid4().hex, "interactionType": "userPrompt",
                                                  "appClass": "IPM.SkypeTeams.Message.Copilot.BizChat",
                                                  "createdDateTime": now,
                                                  "body": {"content": "Research Contoso and draft an account brief"}})
        elif (use_case, step) == ("cowork-sales-brief", "step-2"):
            self.file(upn, "Contoso pitch.pptx", "Contoso pitch deck - why now, solution, pricing")
            if with_copilot:
                u["copilot_audit"].append({"createdDateTime": now, "operation": "CopilotInteraction",
                                           "auditData": {"AppIdentity": "Copilot.MicrosoftCopilot.Cowork"}})
        elif (use_case, step) == ("cowork-sales-brief", "step-3"):
            u["sent_messages"].append({"id": uuid.uuid4().hex, "subject": "Contoso account brief", "sentDateTime": now,
                                       "toRecipients": [{"emailAddress": {"address": "manager@ignite.demo"}}],
                                       "hasAttachments": True, "bodyPreview": "Brief attached."})
        elif (use_case, step) == ("cowork-sales-brief", "step-4"):
            u["calendar_events"].append({"id": uuid.uuid4().hex, "subject": "Contoso account review",
                                         "createdDateTime": now, "isOnlineMeeting": True,
                                         "attendees": [{"emailAddress": {"address": "manager@ignite.demo"}}]})
        elif (use_case, step) == ("cowork-weekly-report", "step-1"):
            self.file(upn, "Weekly revenue.xlsx", "Region Revenue Target EMEA 1.2M AMER 2.1M")
        elif (use_case, step) == ("cowork-weekly-report", "step-2"):
            u["sent_messages"].append({"id": uuid.uuid4().hex, "subject": "Weekly revenue summary", "sentDateTime": now,
                                       "toRecipients": [{"emailAddress": {"address": "team@ignite.demo"}}],
                                       "hasAttachments": False, "bodyPreview": "Numbers are in."})

    def save(self) -> None:
        # Merge: another simulator may share this file, so only our own accounts are replaced.
        current = {"users": {}}
        if os.path.exists(self.path):
            try:
                with open(self.path) as fh:
                    current = json.load(fh)
            except ValueError:
                pass
        current.setdefault("users", {}).update(self.data["users"])
        tmp = f"{self.path}.{os.getpid()}.tmp"
        with open(tmp, "w") as fh:
            json.dump(current, fh)
        os.replace(tmp, self.path)  # atomic, so the worker never reads half a file


class Vendor:
    def __init__(self, api: str, creds: dict) -> None:
        self.api = api.rstrip("/")
        self.creds = creds
        self.http = httpx.Client(timeout=30)
        self.token, self.expires = "", 0.0

    def bearer(self) -> dict:
        if time.time() > self.expires - 60:
            r = self.http.post(f"{self.api}/oauth/token", data={
                "grant_type": "client_credentials", "client_id": self.creds["client_id"],
                "client_secret": self.creds["client_secret"]})
            r.raise_for_status()
            body = r.json()
            self.token, self.expires = body["access_token"], time.time() + body["expires_in"]
            print(f"[handshake] token issued for {self.creds['client_id']} (expires in {body['expires_in']}s)")
        return {"Authorization": f"Bearer {self.token}"}

    def complete(self, p: dict, use_case: str, step: str) -> dict:
        payload = {
            "event_id": self.creds.get("event_id", "ignite-2026"), "use_case_id": use_case, "step_id": step,
            "lab": {"lab_profile_id": "SKL-COWORK-01", "lab_instance_id": p["instance"],
                    "lab_started_at": p["lab_started_at"]},
            "participant": {"external_id": p["external_id"], "first_name": p["first"], "last_name": p["last"],
                            "email": p["email"]},
            "lab_account": {"upn": p["upn"]},
            "submitted_at": iso(datetime.now(timezone.utc)),
        }
        r = self.http.post(f"{self.api}/v1/steps/complete", json=payload,
                           headers={**self.bearer(), "Idempotency-Key": str(uuid.uuid4())})
        r.raise_for_status()
        return r.json()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:8080")
    ap.add_argument("--credentials", default="samples/local/demo_credentials.json")
    ap.add_argument("--mock-file", default="samples/local/mock_graph.json")
    ap.add_argument("--participants", type=int, default=40)
    ap.add_argument("--speed", type=float, default=1.0, help="higher = faster")
    ap.add_argument("--fail-rate", type=float, default=0.18, help="chance a click happens before the work is done")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--first-account", type=int, default=1, help="number of the first labuserNNN account")
    ap.add_argument("--no-api", action="store_true",
                    help="only create Microsoft 365 evidence; never call the API (exercise organiser sync instead)")
    args = ap.parse_args()

    rnd = random.Random(args.seed)
    for _ in range(60):
        if os.path.exists(args.credentials):
            break
        time.sleep(1)
    with open(args.credentials) as fh:
        creds = json.load(fh)
    vendor = Vendor(args.api, creds)
    tenant = MockTenant(args.mock_file)
    for _ in range(0 if args.no_api else 60):
        try:
            vendor.bearer()
            break
        except httpx.HTTPError:
            time.sleep(2)

    now = datetime.now(timezone.utc)
    people = []
    for i in range(args.participants):
        n = i + args.first_account - 1
        first, last = FIRST[n % len(FIRST)], LAST[(n * 7 + n // len(FIRST)) % len(LAST)]
        people.append({
            "external_id": f"skl-{10000 + n}", "first": first, "last": last,
            "email": f"{first.lower()}.{last.lower()}@attendee.example".replace("á", "a"),
            "upn": f"labuser{i + args.first_account:03d}@ignite.demo", "instance": f"inst-{uuid.uuid4().hex[:8]}",
            "lab_started_at": iso(now - timedelta(seconds=rnd.randint(30, 600))),
            "pace": rnd.uniform(0.6, 1.8), "step": 0, "next": time.time() + rnd.uniform(1, 20) / args.speed,
            "pending_fix": False, "quit_after": rnd.choice([len(STEPS)] * 6 + [2, 3, 4]),
        })
    for p in people:
        tenant.profile(p)
    tenant.save()
    print(f"[sim] {len(people)} participants, fail rate {args.fail_rate:.0%}, "
          f"{'evidence only (use Sync in the admin portal)' if args.no_api else 'calling the partner API'}")

    while any(p["step"] < p["quit_after"] for p in people):
        due = [p for p in people if p["step"] < p["quit_after"] and p["next"] <= time.time()]
        for p in due:
            use_case, step = STEPS[p["step"]]
            premature = not p["pending_fix"] and rnd.random() < args.fail_rate
            if not premature:
                tenant.evidence(p["upn"], use_case, step, with_copilot=rnd.random() > 0.1)
                tenant.save()
            if args.no_api:
                if not premature:
                    print(f"[work] {p['first']} {p['last']:<10} {use_case}/{step} done in Microsoft 365")
                    p["step"] += 1
                p["next"] = time.time() + rnd.uniform(8, 35) * p["pace"] / args.speed
                continue
            try:
                result = vendor.complete(p, use_case, step)
            except httpx.HTTPError as exc:
                print(f"[sim] {p['upn']} {use_case}/{step} -> HTTP error {exc}")
                p["next"] = time.time() + 5
                continue
            print(f"[click] {p['first']} {p['last']:<10} {use_case}/{step} -> {result['status']} ({result['submission_id'][:8]})")
            if premature:
                p["pending_fix"] = True  # they'll do the work and click again
                # Not scaled by --speed: the fix must land after the step's retry window, or the
                # premature click would (correctly) turn complete while still evaluating.
                p["next"] = time.time() + rnd.uniform(60, 90)
            else:
                p["pending_fix"] = False
                p["step"] += 1
                p["next"] = time.time() + rnd.uniform(8, 35) * p["pace"] / args.speed
        time.sleep(0.3)
    print("[sim] all simulated participants finished")


if __name__ == "__main__":
    main()
