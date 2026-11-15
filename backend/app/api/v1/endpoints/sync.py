from typing import Annotated, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.auth import ErrorResponse
from app.schemas.sync import (
    PullResponse,
    PushBatchRequest,
    PushBatchResponse,
    ResolveConflictRequest,
)
from app.schemas.transaction import TransactionRecord
from app.services.sync_service import (
    process_pull_changes,
    process_push_batch,
    resolve_conflict_item,
)

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post(
    "/push",
    response_model=PushBatchResponse,
    responses={401: {"model": ErrorResponse}}
)
def push_batch(
    data: PushBatchRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)]
):
    return process_push_batch(db, current_user, data)


@router.get(
    "/pull",
    response_model=PullResponse,
    responses={401: {"model": ErrorResponse}}
)
def pull_changes(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
    cursor: Optional[str] = Query(None, description="ISO timestamp from previous pull"),
    limit: int = Query(100, ge=1, le=500, description="Items limit")
):
    return process_pull_changes(db, current_user, cursor=cursor, limit=limit)


@router.post(
    "/resolve-conflict",
    response_model=TransactionRecord,
    responses={400: {"model": ErrorResponse}, 401: {"model": ErrorResponse}}
)
def resolve_conflict(
    data: ResolveConflictRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)]
):
    return resolve_conflict_item(db, current_user, data)
