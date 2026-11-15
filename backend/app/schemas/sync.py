import uuid
from datetime import date as dt_date, datetime as dt_datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel
from app.schemas.transaction import TransactionRecord, TransactionType


class OutboxAction(str, Enum):
    create = "create"
    update = "update"
    delete = "delete"


class PushItem(BaseModel):
    id: uuid.UUID
    action: OutboxAction
    base_version: int
    amount: Optional[int] = None
    type: Optional[TransactionType] = None
    category: Optional[str] = None
    note: Optional[str] = None
    date: Optional[dt_date] = None
    client_updated_at: dt_datetime


class PushBatchRequest(BaseModel):
    batch_id: uuid.UUID
    items: list[PushItem]


class PushAppliedItem(BaseModel):
    id: uuid.UUID
    version: int
    updated_at: dt_datetime


class PushConflictItem(BaseModel):
    id: uuid.UUID
    conflict_reason: str
    server_record: Optional[TransactionRecord] = None


class PushBatchResponse(BaseModel):
    batch_id: uuid.UUID
    applied: list[PushAppliedItem]
    conflicts: list[PushConflictItem]


class PullResponse(BaseModel):
    items: list[TransactionRecord]
    next_cursor: Optional[str] = None
    has_more: bool


class ConflictResolution(str, Enum):
    use_client = "use_client"
    use_server = "use_server"


class ClientTransactionData(BaseModel):
    amount: Optional[int] = None
    type: Optional[TransactionType] = None
    category: Optional[str] = None
    note: Optional[str] = None
    date: Optional[dt_date] = None


class ResolveConflictRequest(BaseModel):
    id: uuid.UUID
    resolution: ConflictResolution
    target_version: int
    client_data: Optional[ClientTransactionData] = None
