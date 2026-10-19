"""Seed a demo event, Cowork use cases and a test vendor integration. Idempotent.

    python -m app.seed_demo --credentials-out /app/samples/local/demo_credentials.json
"""
import argparse
import asyncio
import json
import os
from pathlib import Path

from sqlalchemy import select

from app.db import SessionLocal
from app.models import Event, Integration, Step, UseCase
from app.rubric import parse_rubric
from app.security import generate_client_id, generate_client_secret, hash_secret

RUBRICS = Path(__file__).resolve().parent.parent / "samples" / "rubrics"

USE_CASES = [
    ("cowork-sales-brief", "Account brief with Copilot Cowork",
     "Use Cowork to research Contoso, produce a brief and a deck, then brief your manager.", [
         ("step-1", "Draft the Contoso account brief", "brief.yaml"),
         ("step-2", "Turn the brief into a pitch deck", "deck.yaml"),
         ("step-3", "Email the brief to your manager", "email.yaml"),
         ("step-4", "Schedule the account review", "meeting.yaml"),
     ]),
    ("cowork-weekly-report", "Weekly report automation",
     "Have Cowork compile the weekly revenue workbook and send the summary.", [
         ("step-1", "Compile the revenue workbook", "workbook.yaml"),
         ("step-2", "Send the weekly summary", "summary-mail.yaml"),
     ]),
]


async def seed(credentials_out: str | None) -> None:
    async with SessionLocal() as session:
        event = (await session.execute(select(Event).where(Event.slug == "ignite-2026"))).scalar_one_or_none()
        if event is None:
            event = Event(slug="ignite-2026", name="Microsoft Ignite 2026 - Copilot Cowork Challenge",
                          description="Hands-on Copilot Cowork labs. Click Complete in your lab after each step.",
                          status="live", public_leaderboard=True, public_name_format="first_last_initial")
            session.add(event)
            await session.flush()
        for ui, (code, title, desc, steps) in enumerate(USE_CASES):
            uc = (await session.execute(select(UseCase).where(
                UseCase.event_id == event.id, UseCase.code == code))).scalar_one_or_none()
            if uc is None:
                uc = UseCase(event_id=event.id, code=code, title=title, description=desc, sort_order=ui)
                session.add(uc)
                await session.flush()
            for si, (scode, stitle, rubric_file) in enumerate(steps):
                exists = (await session.execute(select(Step).where(
                    Step.use_case_id == uc.id, Step.code == scode))).scalar_one_or_none()
                if exists:
                    continue
                text = (RUBRICS / rubric_file).read_text()
                session.add(Step(use_case_id=uc.id, code=scode, title=stitle, sort_order=si, rubric_yaml=text,
                                 rubric_json=parse_rubric(text).model_dump()))

        integration = (await session.execute(select(Integration).where(
            Integration.name == "Demo lab partner"))).scalar_one_or_none()
        secret = os.environ.get("VS_DEMO_CLIENT_SECRET") or generate_client_secret()
        if integration is None:
            integration = Integration(name="Demo lab partner", vendor="Demo Labs",
                                      client_id=os.environ.get("VS_DEMO_CLIENT_ID") or generate_client_id(),
                                      secret_hash=hash_secret(secret), secret_hint=secret[-4:],
                                      webhook_secret="whsec_demo")
            session.add(integration)
        else:
            integration.secret_hash, integration.secret_hint = hash_secret(secret), secret[-4:]
        await session.commit()

        if credentials_out:
            Path(credentials_out).parent.mkdir(parents=True, exist_ok=True)
            Path(credentials_out).write_text(json.dumps(
                {"client_id": integration.client_id, "client_secret": secret, "event_id": event.slug}, indent=2))
        print(f"seeded event '{event.slug}' and integration {integration.client_id}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials-out")
    args = parser.parse_args()
    asyncio.run(seed(args.credentials_out))
