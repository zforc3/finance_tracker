from typing import Annotated
from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.auth import (
    ErrorResponse,
    LoginRequest,
    RefreshTokenRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from app.services.auth_service import (
    authenticate_user,
    issue_token_pair,
    refresh_tokens,
    register_user,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
    responses={400: {"model": ErrorResponse}}
)
def register(
    data: RegisterRequest,
    db: Annotated[Session, Depends(get_db)]
):
    return register_user(db, data)


@router.post(
    "/login",
    response_model=TokenResponse,
    responses={401: {"model": ErrorResponse}}
)
def login(
    data: LoginRequest,
    db: Annotated[Session, Depends(get_db)]
):
    user = authenticate_user(db, data.email, data.password)
    return issue_token_pair(db, user)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    responses={401: {"model": ErrorResponse}}
)
def refresh(
    data: RefreshTokenRequest,
    db: Annotated[Session, Depends(get_db)]
):
    return refresh_tokens(db, data.refresh_token)


@router.get(
    "/me",
    response_model=UserResponse,
    responses={401: {"model": ErrorResponse}}
)
def get_me(
    current_user: Annotated[User, Depends(get_current_user)]
):
    return current_user
