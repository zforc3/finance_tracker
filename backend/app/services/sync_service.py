from datetime import datetime, timezone
from typing import Optional
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models.sync_log import SyncBatchLog
from app.models.transaction import Transaction
from app.models.user import User
from app.schemas.sync import (
    ConflictResolution,
    OutboxAction,
    PullResponse,
    PushAppliedItem,
    PushBatchRequest,
    PushBatchResponse,
    PushConflictItem,
    ResolveConflictRequest,
)
from app.schemas.transaction import TransactionRecord


def process_push_batch(db: Session, user: User, batch: PushBatchRequest) -> PushBatchResponse:
    existing_log = db.query(SyncBatchLog).filter(
        SyncBatchLog.id == batch.batch_id,
        SyncBatchLog.user_id == user.id
    ).first()

    applied: list[PushAppliedItem] = []
    conflicts: list[PushConflictItem] = []

    if existing_log:
        for item in batch.items:
            tx = db.query(Transaction).filter(
                Transaction.id == item.id,
                Transaction.user_id == user.id
            ).first()
            if tx:
                applied.append(PushAppliedItem(id=tx.id, version=tx.version, updated_at=tx.updated_at))
        return PushBatchResponse(batch_id=batch.batch_id, applied=applied, conflicts=[])

    now = datetime.now(timezone.utc)

    for item in batch.items:
        tx = db.query(Transaction).filter(
            Transaction.id == item.id,
            Transaction.user_id == user.id
        ).first()

        if item.action == OutboxAction.create:
            if tx:
                if tx.version == 1:
                    applied.append(PushAppliedItem(id=tx.id, version=tx.version, updated_at=tx.updated_at))
                else:
                    conflicts.append(PushConflictItem(
                        id=item.id,
                        conflict_reason="Record already exists with version > 1",
                        server_record=TransactionRecord.model_validate(tx)
                    ))
            else:
                new_tx = Transaction(
                    id=item.id,
                    user_id=user.id,
                    amount=item.amount or 0,
                    type=item.type.value if item.type else "expense",
                    category=item.category or "General",
                    note=item.note,
                    date=item.date or now.date(),
                    version=1,
                    deleted_at=None,
                    created_at=item.client_updated_at or now,
                    updated_at=item.client_updated_at or now,
                )
                db.add(new_tx)
                db.flush()
                applied.append(PushAppliedItem(id=new_tx.id, version=new_tx.version, updated_at=new_tx.updated_at))

        elif item.action == OutboxAction.update:
            if not tx:
                conflicts.append(PushConflictItem(
                    id=item.id,
                    conflict_reason="Record not found on server",
                    server_record=None
                ))
            elif tx.version != item.base_version:
                conflicts.append(PushConflictItem(
                    id=item.id,
                    conflict_reason=f"Version conflict: server is {tx.version}, base was {item.base_version}",
                    server_record=TransactionRecord.model_validate(tx)
                ))
            else:
                if item.amount is not None:
                    tx.amount = item.amount
                if item.type is not None:
                    tx.type = item.type.value
                if item.category is not None:
                    tx.category = item.category
                tx.note = item.note
                if item.date is not None:
                    tx.date = item.date

                tx.version += 1
                tx.updated_at = now
                db.add(tx)
                db.flush()
                applied.append(PushAppliedItem(id=tx.id, version=tx.version, updated_at=tx.updated_at))

        elif item.action == OutboxAction.delete:
            if not tx:
                applied.append(PushAppliedItem(id=item.id, version=item.base_version, updated_at=now))
            elif tx.version != item.base_version:
                conflicts.append(PushConflictItem(
                    id=item.id,
                    conflict_reason=f"Version conflict on delete: server is {tx.version}, base was {item.base_version}",
                    server_record=TransactionRecord.model_validate(tx)
                ))
            else:
                tx.deleted_at = now
                tx.version += 1
                tx.updated_at = now
                db.add(tx)
                db.flush()
                applied.append(PushAppliedItem(id=tx.id, version=tx.version, updated_at=tx.updated_at))

    batch_log = SyncBatchLog(
        id=batch.batch_id,
        user_id=user.id,
        items_count=len(batch.items),
        processed_at=now
    )
    db.add(batch_log)
    db.commit()

    return PushBatchResponse(batch_id=batch.batch_id, applied=applied, conflicts=conflicts)


def process_pull_changes(
    db: Session,
    user: User,
    cursor: Optional[str] = None,
    limit: int = 100
) -> PullResponse:
    limit = min(max(limit, 1), 500)

    query = select(Transaction).where(Transaction.user_id == user.id)

    if cursor:
        try:
            cursor_dt = datetime.fromisoformat(cursor.replace("Z", "+00:00"))
            query = query.where(Transaction.updated_at > cursor_dt)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"error_code": "INVALID_CURSOR", "message": "Cursor must be a valid ISO 8601 timestamp."}
            )

    query = query.order_by(Transaction.updated_at.asc(), Transaction.id.asc()).limit(limit + 1)
    results = list(db.scalars(query).all())

    has_more = len(results) > limit
    items_to_return = results[:limit]

    records = [TransactionRecord.model_validate(tx) for tx in items_to_return]
    next_cursor = items_to_return[-1].updated_at.isoformat() if items_to_return else cursor

    return PullResponse(
        items=records,
        next_cursor=next_cursor,
        has_more=has_more
    )


def resolve_conflict_item(db: Session, user: User, data: ResolveConflictRequest) -> TransactionRecord:
    tx = db.query(Transaction).filter(
        Transaction.id == data.id,
        Transaction.user_id == user.id
    ).first()

    if not tx:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "NOT_FOUND", "message": "Transaction not found."}
        )

    now = datetime.now(timezone.utc)

    if data.resolution == ConflictResolution.use_client:
        if not data.client_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={"error_code": "MISSING_CLIENT_DATA", "message": "client_data is required for use_client."}
            )
        cd = data.client_data
        if cd.amount is not None:
            tx.amount = cd.amount
        if cd.type is not None:
            tx.type = cd.type.value
        if cd.category is not None:
            tx.category = cd.category
        tx.note = cd.note
        if cd.date is not None:
            tx.date = cd.date

        tx.deleted_at = None
        tx.version = data.target_version + 1
        tx.updated_at = now
        db.add(tx)
        db.commit()
        db.refresh(tx)
    else:
        pass

    return TransactionRecord.model_validate(tx)
