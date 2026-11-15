from datetime import datetime, timedelta, timezone
from typing import Any, Optional
import hashlib
import jwt
from passlib.context import CryptContext
from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_access_token(subject: str | Any, expires_delta: Optional[timedelta] = None) -> tuple[str, int]:
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
        expires_in = int(expires_delta.total_seconds())
    else:
        expires_in = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        expire = datetime.now(timezone.utc) + timedelta(seconds=expires_in)

    to_encode = {
        "exp": expire,
        "sub": str(subject),
        "type": "access"
    }
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt, expires_in


def create_refresh_token(subject: str | Any, expires_delta: Optional[timedelta] = None) -> tuple[str, datetime]:
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    to_encode = {
        "exp": expire,
        "sub": str(subject),
        "type": "refresh"
    }
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt, expire


def decode_token(token: str) -> dict[str, Any]:
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
