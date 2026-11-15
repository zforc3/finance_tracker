from datetime import datetime, timezone
import jwt
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_password_hash,
    hash_token,
    verify_password,
)
from app.models.user import RefreshToken, User
from app.schemas.auth import RegisterRequest, TokenResponse


def register_user(db: Session, data: RegisterRequest) -> User:
    existing_user = db.query(User).filter(User.email == data.email.lower()).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error_code": "EMAIL_ALREADY_EXISTS", "message": "Email is already registered."}
        )

    user = User(
        email=data.email.lower(),
        hashed_password=get_password_hash(data.password)
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def authenticate_user(db: Session, email: str, password: str) -> User:
    user = db.query(User).filter(User.email == email.lower()).first()
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "INVALID_CREDENTIALS", "message": "Incorrect email or password."}
        )
    return user


def issue_token_pair(db: Session, user: User) -> TokenResponse:
    access_token, expires_in = create_access_token(user.id)
    refresh_token, expires_at = create_refresh_token(user.id)

    db_refresh_token = RefreshToken(
        user_id=user.id,
        token_hash=hash_token(refresh_token),
        expires_at=expires_at,
        revoked=False
    )
    db.add(db_refresh_token)
    db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        expires_in=expires_in
    )


def refresh_tokens(db: Session, refresh_token_str: str) -> TokenResponse:
    try:
        payload = decode_token(refresh_token_str)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "TOKEN_EXPIRED", "message": "Refresh token has expired."}
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "INVALID_TOKEN", "message": "Invalid refresh token."}
        )

    if payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "INVALID_TOKEN_TYPE", "message": "Invalid token type, expected refresh token."}
        )

    user_id_str = payload.get("sub")
    hashed = hash_token(refresh_token_str)

    stored_token = db.query(RefreshToken).filter(
        RefreshToken.token_hash == hashed,
        RefreshToken.revoked.is_(False)
    ).first()

    now = datetime.now(timezone.utc)
    if not stored_token or stored_token.expires_at < now:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "TOKEN_REVOKED_OR_EXPIRED", "message": "Refresh token is invalid or revoked."}
        )

    stored_token.revoked = True
    db.add(stored_token)

    user = db.query(User).filter(User.id == stored_token.user_id).first()
    if not user:
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error_code": "USER_NOT_FOUND", "message": "User associated with token not found."}
        )

    return issue_token_pair(db, user)
