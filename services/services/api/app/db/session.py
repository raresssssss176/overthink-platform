"""Engine și dependency de sesiune, de importat în modulele viitoare."""
import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

load_dotenv(Path(__file__).resolve().parents[4] / '.env')

@lru_cache(maxsize=1)
def get_session_factory() -> sessionmaker[Session]:
    url = os.getenv('DATABASE_URL')
    if not url:
        raise RuntimeError('Configurează DATABASE_URL în .env')
    engine = create_engine(url, pool_pre_ping=True)
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

def get_db():
    factory = get_session_factory()
    with factory() as session:
        yield session
