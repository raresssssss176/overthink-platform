from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Department
from app.schemas import DepartmentOut

router = APIRouter(tags=["catalog"])


@router.get("/departments", response_model=list[DepartmentOut])
def list_departments(db: Session = Depends(get_db)):
    """Public list of active departments, used by the registration form."""
    return db.scalars(
        select(Department).where(Department.is_active.is_(True)).order_by(Department.name)
    ).all()