from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class APNSConfig:
    team_id: str
    key_id: str
    bundle_id: str
    private_key: str
    environment: str = "sandbox"

    @property
    def host(self) -> str:
        if self.environment == "production":
            return "https://api.push.apple.com"
        return "https://api.sandbox.push.apple.com"

    @property
    def is_configured(self) -> bool:
        return all([self.team_id, self.key_id, self.bundle_id, self.private_key])


class APNSConfigurationError(RuntimeError):
    pass


class APNSDeliveryError(RuntimeError):
    def __init__(self, status_code: int, response_body: str) -> None:
        self.status_code = status_code
        self.response_body = response_body
        detail = f"APNs returned HTTP {status_code}"
        if response_body:
            detail = f"{detail}: {response_body}"
        super().__init__(detail)


class APNSSender:
    def __init__(self, config: APNSConfig) -> None:
        self.config = config

    async def send_alert(
        self,
        device_token: str,
        title: str,
        body: str,
        user_info: dict[str, Any],
    ) -> None:
        if not self.config.is_configured:
            raise APNSConfigurationError("APNs is not configured")

        import httpx

        payload = {
            "aps": {
                "alert": {
                    "title": title,
                    "body": body,
                },
                "sound": "default",
            },
            **user_info,
        }
        headers = {
            "authorization": f"bearer {self._jwt()}",
            "apns-topic": self.config.bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        async with httpx.AsyncClient(http2=True, timeout=15) as client:
            response = await client.post(
                f"{self.config.host}/3/device/{device_token}",
                headers=headers,
                json=payload,
            )
            if response.status_code >= 400:
                raise APNSDeliveryError(response.status_code, response.text)

    def _jwt(self) -> str:
        import jwt

        return jwt.encode(
            {
                "iss": self.config.team_id,
                "iat": int(time.time()),
            },
            self.config.private_key,
            algorithm="ES256",
            headers={"kid": self.config.key_id},
        )


def read_private_key(value: str, path: str) -> str:
    if value:
        return value.replace("\\n", "\n")
    if path:
        return Path(path).read_text(encoding="utf-8")
    return ""
