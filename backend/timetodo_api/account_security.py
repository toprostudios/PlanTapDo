"""Account lifecycle primitives kept separate from HTTP presentation code."""

import base64
from datetime import timedelta
import hashlib
import hmac
import secrets
import struct
import time
from urllib.parse import quote

from cryptography.fernet import Fernet, InvalidToken, MultiFernet
from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework_simplejwt.tokens import RefreshToken

from .models import AuthChallenge, User, UserSession


MAX_CHALLENGE_ATTEMPTS = 5
CHALLENGE_LIFETIME = timedelta(minutes=15)
CHALLENGE_RESEND_COOLDOWN = timedelta(seconds=60)
GENERIC_CHALLENGE_ERROR = "The code is invalid or has expired."
SESSION_ID_CLAIM = "session_id"
SESSION_VERSION_CLAIM = "session_version"


def _fernet() -> MultiFernet:
    return MultiFernet(
        [Fernet(key.encode("ascii")) for key in settings.MFA_ENCRYPTION_KEYS]
    )


def encrypt_mfa_secret(secret: str) -> str:
    return _fernet().encrypt(secret.encode("ascii")).decode("ascii")


def decrypt_mfa_secret(ciphertext: str) -> str:
    try:
        return _fernet().decrypt(ciphertext.encode("ascii")).decode("ascii")
    except (InvalidToken, ValueError) as exc:
        raise ValidationError({"detail": "MFA configuration is unavailable."}) from exc


def generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def totp_code(secret: str, timestamp: int | None = None) -> str:
    timestamp = int(time.time()) if timestamp is None else timestamp
    padded_secret = secret + "=" * ((8 - len(secret) % 8) % 8)
    key = base64.b32decode(padded_secret, casefold=True)
    counter = struct.pack(">Q", timestamp // 30)
    # TOTP interoperability requires HMAC-SHA1; this is an authentication code,
    # not a collision-resistance or password-hashing use.
    digest = hmac.new(key, counter, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return f"{value % 1_000_000:06d}"


def verify_totp(secret: str, candidate: str) -> bool:
    normalized = candidate.replace(" ", "").strip()
    if len(normalized) != 6 or not normalized.isdigit():
        return False
    now = int(time.time())
    return any(
        hmac.compare_digest(totp_code(secret, now + offset * 30), normalized)
        for offset in (-1, 0, 1)
    )


def mfa_provisioning_uri(user: User, secret: str) -> str:
    account = quote(user.email or user.username, safe="")
    issuer = quote("PlanTapDo", safe="")
    return (
        f"otpauth://totp/{issuer}:{account}?secret={secret}"
        f"&issuer={issuer}&algorithm=SHA1&digits=6&period=30"
    )


def generate_recovery_codes() -> tuple[list[str], list[str]]:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    codes = [
        "-".join(
            "".join(secrets.choice(alphabet) for _ in range(4))
            for _ in range(3)
        )
        for _ in range(10)
    ]
    return codes, [make_password(code) for code in codes]


def verify_mfa_code(user: User, candidate: str, *, consume_recovery: bool) -> bool:
    if not user.mfa_enabled or not user.mfa_secret_encrypted:
        return True
    if verify_totp(decrypt_mfa_secret(user.mfa_secret_encrypted), candidate):
        return True

    normalized = candidate.strip().upper()
    for index, digest in enumerate(user.mfa_recovery_code_hashes):
        if check_password(normalized, digest):
            if consume_recovery:
                hashes = list(user.mfa_recovery_code_hashes)
                hashes.pop(index)
                user.mfa_recovery_code_hashes = hashes
                user.save(update_fields=["mfa_recovery_code_hashes"])
            return True
    return False


def issue_session_tokens(user: User, client_label: str = "PlanTapDo") -> dict[str, str]:
    now = timezone.now()
    user.sessions.filter(expires_at__lte=now).delete()
    active_sessions = user.sessions.filter(
        revoked_at__isnull=True, expires_at__gt=now
    ).order_by("last_seen_at")
    excess = active_sessions.count() - settings.ACCOUNT_ACTIVE_SESSION_QUOTA + 1
    if excess > 0:
        for old_session in active_sessions[:excess]:
            revoke_session(old_session)
    session = UserSession.objects.create(
        user=user,
        client_label=(client_label.strip() or "PlanTapDo")[:100],
        expires_at=now + settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"],
    )
    refresh = RefreshToken.for_user(user)
    refresh[SESSION_ID_CLAIM] = str(session.id)
    refresh[SESSION_VERSION_CLAIM] = user.session_version
    return {"refresh": str(refresh), "access": str(refresh.access_token)}


def revoke_session(session: UserSession) -> None:
    if session.revoked_at is None:
        session.revoked_at = timezone.now()
        session.save(update_fields=["revoked_at"])
    remaining = max(1, int((session.expires_at - timezone.now()).total_seconds()))
    from django.core.cache import cache

    cache.set(f"revoked-session:{session.id}", True, timeout=remaining)


def revoke_all_user_sessions(user: User) -> None:
    now = timezone.now()
    active_sessions = list(
        user.sessions.filter(revoked_at__isnull=True, expires_at__gt=now)
    )
    user.session_version += 1
    user.save(update_fields=["session_version"])
    for session in active_sessions:
        revoke_session(session)


def _new_challenge(user: User, kind: str) -> tuple[AuthChallenge, str] | None:
    now = timezone.now()
    AuthChallenge.objects.filter(
        user=user, created_at__lt=now - timedelta(days=1)
    ).delete()
    recent = (
        AuthChallenge.objects.filter(user=user, kind=kind, consumed_at__isnull=True)
        .order_by("-created_at")
        .first()
    )
    if recent is not None and recent.created_at > now - CHALLENGE_RESEND_COOLDOWN:
        return None

    AuthChallenge.objects.filter(
        user=user, kind=kind, consumed_at__isnull=True
    ).update(consumed_at=now)
    code = f"{secrets.randbelow(100_000_000):08d}"
    challenge = AuthChallenge.objects.create(
        user=user,
        kind=kind,
        code_digest=make_password(code),
        expires_at=now + CHALLENGE_LIFETIME,
    )
    return challenge, code


def send_challenge(user: User, kind: str) -> None:
    if not user.email:
        return
    result = _new_challenge(user, kind)
    if result is None:
        return
    _challenge, code = result
    purpose = (
        "verify your PlanTapDo email"
        if kind == AuthChallenge.Kind.VERIFY_EMAIL
        else "reset your PlanTapDo password"
    )
    send_mail(
        subject="Your PlanTapDo security code",
        message=(
            f"Use {code} to {purpose}. The code expires in 15 minutes and can "
            "only be used once. If you did not request this, ignore this email."
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[user.email],
        fail_silently=False,
    )


def consume_challenge(email: str, kind: str, code: str) -> User:
    with transaction.atomic():
        user = (
            User.objects.select_for_update()
            .filter(email__iexact=email.strip())
            .first()
        )
        if user is None:
            raise ValidationError({"code": GENERIC_CHALLENGE_ERROR})
        challenge = (
            AuthChallenge.objects.select_for_update()
            .filter(user=user, kind=kind, consumed_at__isnull=True)
            .order_by("-created_at")
            .first()
        )
        now = timezone.now()
        if (
            challenge is None
            or challenge.expires_at <= now
            or challenge.attempts >= MAX_CHALLENGE_ATTEMPTS
        ):
            raise ValidationError({"code": GENERIC_CHALLENGE_ERROR})
        if not check_password(code.strip(), challenge.code_digest):
            challenge.attempts += 1
            challenge.save(update_fields=["attempts"])
            raise ValidationError({"code": GENERIC_CHALLENGE_ERROR})
        challenge.consumed_at = now
        challenge.save(update_fields=["consumed_at"])
        return user
