import uuid
from datetime import date as dt_date, datetime as dt_datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, ConfigDict


class TransactionType(str, Enum):
    income = "income"
    expense = "expense"


class TransactionRecord(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    amount: int
    type: TransactionType
    category: str
    note: Optional[str] = None
    date: dt_date
    version: int
    deleted_at: Optional[dt_datetime] = None
    created_at: dt_datetime
    updated_at: dt_datetime

    model_config = ConfigDict(from_attributes=True)
