from fastapi import FastAPI

from app.config import settings
from app.routers import admin, auth, catalog, users, admin_members, team, audit_view, hours, codes

if settings.env == "prod" and len(settings.jwt_secret) < 32:
    raise RuntimeError("JWT_SECRET must be set (32+ chars) in production")

app = FastAPI(title="Overthink API", version="0.1.0")
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(admin.router)
app.include_router(catalog.router)
app.include_router(admin_members.router)
app.include_router(team.router)
app.include_router(audit_view.router)
app.include_router(hours.router)
app.include_router(codes.router)

@app.get("/health", tags=["meta"])
def health():
    return {"status": "ok"}