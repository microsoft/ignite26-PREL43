"""Evidence sources. Checks talk to an EvidenceSource, never to Graph directly, so mock and live are interchangeable."""
from functools import lru_cache

from app.config import get_settings
from app.graph.base import EvidenceSource


@lru_cache
def get_source() -> EvidenceSource:
    settings = get_settings()
    if settings.graph_mode == "live":
        from app.graph.live import GraphEvidenceSource

        return GraphEvidenceSource(settings)
    from app.graph.mock import MockEvidenceSource

    return MockEvidenceSource(settings.graph_mock_file)
