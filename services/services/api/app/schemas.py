import uuid
from datetime import date, datetime

from pydantic import BaseModel, EmailStr, Field, model_validator

Name = Field(min_length=1, max_length=100)


class RegisterIn(BaseModel):
    first_name: str = Name
    last_name: str = Name
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)
    confirm_password: str
    birth_date: date
    school: str = Field(min_length=1, max_length=200)
    locality: str = Field(min_length=1, max_length=120)
    accepted_privacy_policy: bool

    @model_validator(mode="after")
    def _check(self):
        if self.password != self.confirm_password:
            raise ValueError("Passwords do not match")
        if not self.accepted_privacy_policy:
            raise ValueError("The privacy notice must be accepted")
        if self.birth_date >= date.today():
            raise ValueError("Invalid birth date")
        return self


class TokenIn(BaseModel):
    token: str = Field(min_length=10, max_length=200)


class VerifyEmailCodeIn(BaseModel):
    email: EmailStr
    code: str = Field(pattern=r"^\d{6}$")


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str


class EmailIn(BaseModel):
    email: EmailStr


class ResetPasswordIn(BaseModel):
    token: str
    new_password: str = Field(min_length=10, max_length=128)


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str = Field(min_length=10, max_length=128)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    account_status: str


class Message(BaseModel):
    message: str


class ProfileOut(BaseModel):
    id: uuid.UUID
    first_name: str
    last_name: str
    email: EmailStr
    birth_date: date | None
    school: str | None
    locality: str | None
    primary_department_id: uuid.UUID | None
    profile_photo_key: str | None
    approved_minutes_cached: int
    joined_at: datetime | None
    account_status: str

    model_config = {"from_attributes": True}


class MembershipStatusOut(BaseModel):
    decision: str
    submitted_at: datetime
    review_deadline_at: datetime
    rejection_reason: str | None
    can_remind: bool
    next_reminder_at: datetime | None


class PendingRequestOut(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    first_name: str
    last_name: str
    email: EmailStr
    birth_date: date
    school: str
    locality: str
    submitted_at: datetime
    review_deadline_at: datetime
    overdue: bool
    reminder_count: int
    last_reminder_at: datetime | None


class RejectIn(BaseModel):
    reason: str = Field(min_length=3, max_length=500)
